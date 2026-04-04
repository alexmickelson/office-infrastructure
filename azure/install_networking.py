#!/usr/bin/env nix-shell
#!nix-shell shell.nix -i python3

import subprocess
import sys
import time

from common import (
    _AZ_ENV,
    cluster_exists,
    ensure_logged_in,
    load_config,
    prompt,
    resource_group_exists,
    run,
)


def gateway_api_enabled(cfg: dict) -> bool:
    """Check whether Gateway API CRDs are installed on the cluster."""
    cmd = [
        "kubectl", "--kubeconfig", cfg["kubeconfig"],
        "get", "crd", "gateways.gateway.networking.k8s.io",
        "--ignore-not-found", "--output", "name",
    ]
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True, env=_AZ_ENV)
    return bool(result.stdout.strip())


def enable_gateway_api(cfg: dict) -> None:
    """Register the preview feature flag, wait for it, then enable Gateway API CRDs."""
    # 1. Register the feature (idempotent)
    run([
        "az", "feature", "register",
        "--namespace", "Microsoft.ContainerService",
        "--name", "ManagedGatewayAPIPreview",
    ])

    # 2. Wait until Registered
    print("  Waiting for ManagedGatewayAPIPreview to be Registered (this can take a few minutes)...")
    while True:
        result = subprocess.run([
            "az", "feature", "show",
            "--namespace", "Microsoft.ContainerService",
            "--name", "ManagedGatewayAPIPreview",
            "--query", "properties.state",
            "--output", "tsv",
        ], capture_output=True, text=True, env=_AZ_ENV)
        state = result.stdout.strip()
        print(f"  state: {state}")
        if state == "Registered":
            break
        time.sleep(15)

    # 3. Propagate the registration to the provider and wait
    run([
        "az", "provider", "register",
        "--namespace", "Microsoft.ContainerService",
    ])
    print("  Waiting for Microsoft.ContainerService provider to finish registering...")
    while True:
        result = subprocess.run([
            "az", "provider", "show",
            "--namespace", "Microsoft.ContainerService",
            "--query", "registrationState",
            "--output", "tsv",
        ], capture_output=True, text=True, env=_AZ_ENV)
        state = result.stdout.strip()
        print(f"  provider state: {state}")
        if state == "Registered":
            break
        time.sleep(15)
    print("  Provider registered. Waiting 30s for backend propagation...")
    time.sleep(30)

    # 4. Enable on the cluster
    run([
        "az", "aks", "update",
        "--resource-group", cfg["resource_group"],
        "--name", cfg["name"],
        "--enable-gateway-api",
    ])


def check_gateway_api(cfg: dict) -> None:
    """Ensure Gateway API CRDs are installed; prompt to enable if not."""
    if not cfg.get("gateway_api", {}).get("enabled"):
        print("  Gateway API is not enabled in config. Skipping.")
        return
    if gateway_api_enabled(cfg):
        print("  [ok] Gateway API CRDs are installed.")
        return
    print("  [!] Gateway API CRDs are NOT installed on this cluster.")
    if prompt("Enable Gateway API CRDs now? (requires aks-preview extension)"):
        enable_gateway_api(cfg)


def main() -> None:
    ensure_logged_in()
    cfg = load_config()

    rg_exists = resource_group_exists(cfg)
    aks_exists = rg_exists and cluster_exists(cfg)

    if not aks_exists:
        print(f"  Cluster '{cfg['name']}' does not exist. Nothing to configure.")
        sys.exit(1)

    check_gateway_api(cfg)


if __name__ == "__main__":
    main()
