#!/usr/bin/env nix-shell
#!nix-shell shell.nix -i python3

import sys
from pathlib import Path

from common import (
    cluster_exists,
    ensure_logged_in,
    load_config,
    resource_group_exists,
    run,
)


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
    print(f"\nKubeconfig written to: {kubeconfig}")


def main() -> None:
    ensure_logged_in()
    cfg = load_config()

    if not resource_group_exists(cfg):
        print(f"Resource group '{cfg['resource_group']}' does not exist.", file=sys.stderr)
        sys.exit(1)

    if not cluster_exists(cfg):
        print(f"Cluster '{cfg['name']}' does not exist in resource group '{cfg['resource_group']}'.", file=sys.stderr)
        sys.exit(1)

    get_credentials(cfg)


if __name__ == "__main__":
    main()
