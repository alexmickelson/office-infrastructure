#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.huggingface-hub

import argparse
import os
import sys
from typing import List, Tuple
import shutil

from huggingface_hub import HfApi, hf_hub_download
from huggingface_hub.utils import EntryNotFoundError, HfHubHTTPError


output_directory = "/data/models"


def human_size(size: int | None) -> str:
    if not size:
        return "unknown"
    gb = size / (1024**3)
    if gb >= 1:
        return f"{gb:.2f} GB"
    mb = size / (1024**2)
    return f"{mb:.2f} MB"


def fetch_gguf_listing(repo_id: str) -> List[Tuple[str, str, int | None]]:
    """Return list of (path, human_size, size_bytes_or_None)."""
    api = HfApi()
    # list_repo_tree returns entries with .path and .size
    entries = api.list_repo_tree(repo_id=repo_id, recursive=True)
    results: List[Tuple[str, str, int | None]] = []
    for e in entries:
        if e.path.endswith(".gguf"):
            hs = human_size(e.size)
            results.append((e.path, hs, e.size))
    # sort by path
    results.sort(key=lambda x: x[0].lower())
    return results


def print_menu(files: List[Tuple[str, str, int | None]]) -> None:
    if not files:
        print("No .gguf files found. Exiting.", file=sys.stderr)
        sys.exit(1)

    # Compute padding for alignment
    maxlen = max(len(path) for path, _, _ in files)
    print("\nAvailable model variants:")
    for i, (path, hs, _) in enumerate(files, start=1):
        # e.g. " 1) <path padded> <size right-aligned-ish>"
        print(f"{i:2d}) {path.ljust(maxlen)}  {hs}")


def choose_index(n: int) -> int:
    while True:
        try:
            sel = input("Select a file to download: ").strip()
            if sel == "":
                print("No selection made. Exiting.")
                sys.exit(0)
            idx = int(sel)
            if 1 <= idx <= n:
                return idx - 1
        except ValueError:
            pass
        print(f"Invalid choice. Enter a number between 1 and {n}.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Download a .gguf file from a Hugging Face repo."
    )
    parser.add_argument(
        "model_id", help="Hugging Face repo id (e.g. unsloth/gemma-3-27b-it-GGUF)"
    )
    parser.add_argument(
        "dest",
        nargs="?",
        default=output_directory,
        help=f"Destination directory (default: {output_directory})",
    )
    args = parser.parse_args()

    repo_id = args.model_id
    dest = args.dest

    os.makedirs(dest, exist_ok=True)

    print(f"Fetching available .gguf files for {repo_id} ...")
    try:
        files = fetch_gguf_listing(repo_id)
    except HfHubHTTPError as e:
        print(f"Error listing repo files: {e}", file=sys.stderr)
        sys.exit(1)

    if not files:
        print("No .gguf files found. Exiting.")
        sys.exit(1)

    print_menu(files)
    idx = choose_index(len(files))

    chosen_path, chosen_hsize, _ = files[idx]
    print(f"You selected: {chosen_path}  {chosen_hsize}")

    try:
        # Download file to destination directory
        local_path = hf_hub_download(
            repo_id=repo_id,
            filename=chosen_path,
            cache_dir=dest,
            local_files_only=False,
        )

        filename_only = os.path.basename(chosen_path)
        final_path = os.path.join(dest, filename_only)
        shutil.copy2(local_path, final_path)
        os.remove(local_path)
        local_path = final_path
    except EntryNotFoundError as e:
        print(
            f"\n404 Not Found for: {chosen_path}\n"
            f"- The file name must match exactly (including subfolders).\n"
            f"- If the repo is private, ensure you are authenticated (HF token in env).\n"
            f"- Error: {e}",
            file=sys.stderr,
        )
        sys.exit(1)
    except HfHubHTTPError as e:
        print(f"\nDownload failed: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Downloaded to {local_path}")


if __name__ == "__main__":
    main()
