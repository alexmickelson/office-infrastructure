#!/usr/bin/env nix-shell
#!nix-shell shell.nix -i python3

import json
import subprocess
import sys
from pathlib import Path

from common import (
    _AZ_ENV,
    cluster_exists,
    ensure_logged_in,
    list_resources,
    load_config,
    prompt,
    resource_group_exists,
    run,
)


def create_resource_group(cfg: dict) -> None:
    run([
        "az", "group", "create",
        "--name", cfg["resource_group"],
        "--location", cfg["location"],
    ])


def create_cluster(cfg: dict) -> None:
    np = cfg["node_pool"]
    autoscaler = cfg["autoscaler"]
    autoscaler_profile = (
        f"scan-interval={autoscaler['scan_interval']},"
        f"scale-down-unneeded-time={autoscaler['scale_down_unneeded_time']},"
        f"scale-down-delay-after-add={autoscaler['scale_down_delay_after_add']}"
    )

    cmd = [
        "az", "aks", "create",
        "--resource-group", cfg["resource_group"],
        "--name", cfg["name"],
        "--location", cfg["location"],
        "--node-count", str(np["min_count"]),
        "--node-vm-size", np["vm_size"],
        "--vm-set-type", "VirtualMachineScaleSets",
        "--load-balancer-sku", cfg["load_balancer_sku"],
        "--network-plugin", cfg["network_plugin"],
        "--tier", cfg["tier"],
        "--generate-ssh-keys",
    ]

    if autoscaler.get("enabled"):
        cmd += [
            "--enable-cluster-autoscaler",
            "--min-count", str(np["min_count"]),
            "--max-count", str(np["max_count"]),
            "--cluster-autoscaler-profile", autoscaler_profile,
        ]

    if cfg.get("gateway_api", {}).get("enabled"):
        cmd += ["--enable-gateway-api"]

    run(cmd)


def get_credentials(cfg: dict) -> None:
    kubeconfig = cfg["kubeconfig"]
    Path(kubeconfig).parent.mkdir(parents=True, exist_ok=True)
    run([
        "az", "aks", "get-credentials",
        "--resource-group", cfg["resource_group"],
        "--name", cfg["name"],
        "--file", kubeconfig,
        "--overwrite-existing",
    ])


def check_node_pool(cfg: dict) -> None:
    """Fetch the live node pool config and warn on any diffs against local config."""
    np = cfg["node_pool"]
    autoscaler = cfg["autoscaler"]
    cmd = [
        "az", "aks", "nodepool", "list",
        "--resource-group", cfg["resource_group"],
        "--cluster-name", cfg["name"],
        "--output", "json",
    ]
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True, env=_AZ_ENV)
    if result.returncode != 0:
        print("  Warning: could not fetch node pool info.", file=sys.stderr)
        return

    pools = json.loads(result.stdout)
    if not pools:
        print("  Warning: no node pools found.", file=sys.stderr)
        return

    # Use the first (system) node pool
    live = pools[0]
    pool_name = live["name"]
    diffs = []

    def chk(field: str, live_val, cfg_val) -> None:
        if str(live_val).lower() != str(cfg_val).lower():
            diffs.append((field, live_val, cfg_val))

    chk("vm_size",    live.get("vmSize"),           np["vm_size"])
    chk("min_count",  live.get("minCount"),          np["min_count"])
    chk("max_count",  live.get("maxCount"),          np["max_count"])
    chk("autoscaler", live.get("enableAutoScaling"), autoscaler.get("enabled", False))

    if not diffs:
        print("  [ok] Node pool matches configuration.")
        return

    print("\n  [!] Node pool config drift detected:")
    updatable = []
    for field, live_val, cfg_val in diffs:
        print(f"    {field}: live={live_val!r}  config={cfg_val!r}")
        if field == "vm_size":
            print(f"    (vm_size cannot be changed on an existing node pool)")
        else:
            updatable.append((field, cfg_val))

    if not updatable:
        return

    if not prompt("Update node pool to match configuration?"):
        return

    update_cmd = [
        "az", "aks", "nodepool", "update",
        "--resource-group", cfg["resource_group"],
        "--cluster-name", cfg["name"],
        "--name", pool_name,
    ]

    updatable_fields = {f for f, _ in updatable}
    autoscaler_enabled = autoscaler.get("enabled", False)

    if autoscaler_enabled or "autoscaler" in updatable_fields:
        if "autoscaler" in updatable_fields:
            update_cmd += ["--enable-cluster-autoscaler" if autoscaler_enabled else "--disable-cluster-autoscaler"]
        else:
            update_cmd += ["--update-cluster-autoscaler"]
        update_cmd += ["--min-count", str(np["min_count"]), "--max-count", str(np["max_count"])]

    run(update_cmd)


def main() -> None:
    ensure_logged_in()
    cfg = load_config()

    rg_exists = resource_group_exists(cfg)
    aks_exists = rg_exists and cluster_exists(cfg)

    if aks_exists:
        print(f"\nCluster '{cfg['name']}' already exists in resource group '{cfg['resource_group']}':")
        list_resources(cfg)
        check_node_pool(cfg)
        print()
        if prompt("Fetch kubeconfig credentials?"):
            get_credentials(cfg)
        else:
            print("Nothing to do.")
    else:
        print(f"\nNo cluster '{cfg['name']}' found in resource group '{cfg['resource_group']}'.")
        print(f"  VM size:  {cfg['node_pool']['vm_size']}")
        print(f"  Location: {cfg['location']}")
        print(f"  Nodes:    {cfg['node_pool']['min_count']}–{cfg['node_pool']['max_count']} (autoscaler)")
        print()
        if not prompt("Create the cluster?"):
            print("Aborted.")
            sys.exit(0)
        create_resource_group(cfg)
        create_cluster(cfg)
        get_credentials(cfg)


if __name__ == "__main__":
    main()
