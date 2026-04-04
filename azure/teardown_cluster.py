#!/usr/bin/env nix-shell
#!nix-shell shell.nix -i python3

import sys

from common import (
    cluster_exists,
    ensure_logged_in,
    list_resources,
    load_config,
    prompt,
    resource_group_exists,
    run,
)


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


def main() -> None:
    ensure_logged_in()
    cfg = load_config()

    rg_exists = resource_group_exists(cfg)
    aks_exists = rg_exists and cluster_exists(cfg)

    if not aks_exists:
        print(f"  No cluster '{cfg['name']}' found in resource group '{cfg['resource_group']}'. Nothing to tear down.")
        sys.exit(0)

    print(f"\nResources found for cluster '{cfg['name']}' in resource group '{cfg['resource_group']}':")
    list_resources(cfg)
    print()

    if not prompt("Delete everything? This cannot be undone."):
        print("Aborted.")
        sys.exit(0)

    teardown(cfg)


if __name__ == "__main__":
    main()
