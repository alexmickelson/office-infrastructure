#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p azure-cli python3 python312Packages.pyyaml kubernetes-helm

import json
import os
import subprocess
import sys
import warnings
import yaml
from pathlib import Path

warnings.filterwarnings("ignore", category=FutureWarning, module="azure")

CONFIG_FILE = Path(__file__).parent / "azure-cluster.yml"

# Suppress Python warnings in child az processes
_AZ_ENV = {**os.environ, "PYTHONWARNINGS": "ignore"}


def load_config() -> dict:
    with open(CONFIG_FILE) as f:
        cfg = yaml.safe_load(f)["cluster"]
    cfg["kubeconfig"] = str(Path(cfg["kubeconfig"]).expanduser())
    return cfg


def run(cmd: list[str]) -> None:
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(cmd, env=_AZ_ENV)
    if result.returncode != 0:
        print(f"Command failed with exit code {result.returncode}", file=sys.stderr)
        sys.exit(result.returncode)


def check_logged_in() -> bool:
    cmd = ["az", "account", "show"]
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=_AZ_ENV)
    return result.returncode == 0


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


def delete_cluster(cfg: dict) -> None:
    run([
        "az", "aks", "delete",
        "--resource-group", cfg["resource_group"],
        "--name", cfg["name"],
        "--yes", "--no-wait",
    ])


def delete_resource_group(cfg: dict) -> None:
    run([
        "az", "group", "delete",
        "--name", cfg["resource_group"],
        "--yes", "--no-wait",
    ])


def teardown(cfg: dict) -> None:
    """Delete everything: cluster + resource group."""
    delete_cluster(cfg)
    delete_resource_group(cfg)


def resource_group_exists(cfg: dict) -> bool:
    cmd = ["az", "group", "show", "--name", cfg["resource_group"]]
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=_AZ_ENV)
    return result.returncode == 0


def cluster_exists(cfg: dict) -> bool:
    cmd = ["az", "aks", "show", "--resource-group", cfg["resource_group"], "--name", cfg["name"]]
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=_AZ_ENV)
    return result.returncode == 0


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

    # If autoscaler is enabled (or being enabled), min+max must always be provided together
    if autoscaler_enabled or "autoscaler" in updatable_fields:
        if "autoscaler" in updatable_fields:
            update_cmd += ["--enable-cluster-autoscaler" if autoscaler_enabled else "--disable-cluster-autoscaler"]
        else:
            update_cmd += ["--update-cluster-autoscaler"]
        update_cmd += ["--min-count", str(np["min_count"]), "--max-count", str(np["max_count"])]
    else:
        # Autoscaler disabled — min/max not applicable
        pass

    run(update_cmd)




def nginx_ingress_installed(cfg: dict) -> bool:
    cmd = [
        "helm", "status", "ingress-nginx",
        "--namespace", cfg["nginx_ingress"]["namespace"],
        "--kubeconfig", cfg["kubeconfig"],
    ]
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=_AZ_ENV)
    return result.returncode == 0


def install_nginx_ingress(cfg: dict) -> None:
    ni = cfg["nginx_ingress"]
    run(["helm", "repo", "add", "ingress-nginx", "https://kubernetes.github.io/ingress-nginx"])
    run(["helm", "repo", "update"])
    run([
        "helm", "upgrade", "--install", "ingress-nginx", "ingress-nginx/ingress-nginx",
        "--namespace", ni["namespace"],
        "--create-namespace",
        "--set", "controller.service.type=LoadBalancer",
        "--kubeconfig", cfg["kubeconfig"],
        "--wait",
    ])


def list_resources(cfg: dict) -> None:
    print("\n--- Resource Group ---")
    cmd = ["az", "group", "show", "--name", cfg["resource_group"], "--output", "table"]
    print(f"+ {' '.join(cmd)}")
    subprocess.run(cmd, env=_AZ_ENV)
    print("\n--- AKS Cluster ---")
    cmd = ["az", "aks", "show", "--resource-group", cfg["resource_group"], "--name", cfg["name"], "--output", "table"]
    print(f"+ {' '.join(cmd)}")
    subprocess.run(cmd, env=_AZ_ENV)


def prompt(question: str) -> bool:
    answer = input(f"{question} [y/N] ").strip().lower()
    return answer == "y"


def main() -> None:
    # --- Login check ---
    if not check_logged_in():
        print("Not logged in to Azure.")
        if prompt("Run 'az login' now?"):
            cmd = ["az", "login"]
            print(f"+ {' '.join(cmd)}")
            subprocess.run(cmd, env=_AZ_ENV)
            if not check_logged_in():
                print("Login failed. Exiting.")
                sys.exit(1)
        else:
            print("Cannot continue without login. Exiting.")
            sys.exit(1)

    cfg = load_config()

    # --- Check existing resources ---
    rg_exists = resource_group_exists(cfg)
    aks_exists = rg_exists and cluster_exists(cfg)

    if aks_exists:
        print(f"\nResources already exist for cluster '{cfg['name']}' in resource group '{cfg['resource_group']}':")
        list_resources(cfg)
        check_node_pool(cfg)
        print()
        if prompt("delete everything?"):
            teardown(cfg)
        else:
            if prompt("Fetch kubeconfig credentials?"):
                get_credentials(cfg)
            if cfg.get("nginx_ingress", {}).get("enabled") and not nginx_ingress_installed(cfg):
                if prompt("Install nginx ingress controller?"):
                    install_nginx_ingress(cfg)
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
        if cfg.get("nginx_ingress", {}).get("enabled"):
            print()
            install_nginx_ingress(cfg)


if __name__ == "__main__":
    main()
