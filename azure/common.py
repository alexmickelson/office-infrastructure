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


def ensure_logged_in() -> None:
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
