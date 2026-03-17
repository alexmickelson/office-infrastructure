#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.huggingface-hub

import argparse
import os
import re
import sys
from collections import OrderedDict
from typing import List, Tuple
import shutil

from huggingface_hub import HfApi, hf_hub_download
from huggingface_hub.utils import EntryNotFoundError, HfHubHTTPError


output_directory = "/data/models"

# Matches multi-part files like Foo-00001-of-00005.gguf
MULTIPART_RE = re.compile(r"^(.*)-\d{5}-of-\d{5}\.gguf$")


def human_size(size: int | None) -> str:
    if not size:
        return "unknown"
    gb = size / (1024**3)
    if gb >= 1:
        return f"{gb:.2f} GB"
    mb = size / (1024**2)
    return f"{mb:.2f} MB"


def fetch_gguf_listing(repo_id: str) -> List[Tuple[str, int | None]]:
    """Return list of (path, size_bytes_or_None) for all .gguf files."""
    api = HfApi()
    entries = api.list_repo_tree(repo_id=repo_id, recursive=True)
    results: List[Tuple[str, int | None]] = []
    for e in entries:
        if e.path.endswith(".gguf"):
            results.append((e.path, e.size))
    results.sort(key=lambda x: x[0].lower())
    return results


def group_variants(files: List[Tuple[str, int | None]]) -> List[dict]:
    """
    Group multi-part files (e.g. model-00001-of-00003.gguf) into a single
    variant entry. Single files are their own variant.
    Returns a list of dicts with keys: display, files, total_size.
    """
    groups: OrderedDict[str, dict] = OrderedDict()

    for path, size in files:
        m = MULTIPART_RE.match(path)
        key = m.group(1) if m else path

        if key not in groups:
            groups[key] = {"display": key, "files": [], "total_size": 0}
        groups[key]["files"].append((path, size))
        if size:
            groups[key]["total_size"] += size

    # Ensure parts within each group are in order
    for g in groups.values():
        g["files"].sort(key=lambda x: x[0].lower())

    return list(groups.values())


def print_menu(variants: List[dict]) -> None:
    if not variants:
        print("No .gguf files found. Exiting.", file=sys.stderr)
        sys.exit(1)

    maxlen = max(len(v["display"]) for v in variants)
    print("\nAvailable model variants:")
    for i, v in enumerate(variants, start=1):
        parts = len(v["files"])
        size_str = human_size(v["total_size"] or None)
        label = v["display"].ljust(maxlen)
        suffix = f"  ({parts} parts)" if parts > 1 else ""
        print(f"{i:2d}) {label}  {size_str}{suffix}")


def choose_index(n: int) -> int:
    while True:
        try:
            sel = input("Select a variant to download: ").strip()
            if sel == "":
                print("No selection made. Exiting.")
                sys.exit(0)
            idx = int(sel)
            if 1 <= idx <= n:
                return idx - 1
        except ValueError:
            pass
        print(f"Invalid choice. Enter a number between 1 and {n}.")


def download_variant(repo_id: str, variant: dict, dest: str) -> List[str]:
    """Download all files in the variant, return list of final local paths."""
    downloaded = []
    files = variant["files"]
    total = len(files)
    for i, (path, _) in enumerate(files, start=1):
        if total > 1:
            print(f"  Downloading part {i}/{total}: {os.path.basename(path)}")
        try:
            local_path = hf_hub_download(
                repo_id=repo_id,
                filename=path,
                local_dir=dest,
                local_dir_use_symlinks=False,
            )
            filename_only = os.path.basename(path)
            final_path = os.path.join(dest, filename_only)
            shutil.copy2(local_path, final_path)
            os.remove(local_path)
            downloaded.append(final_path)
        except EntryNotFoundError as e:
            print(
                f"\n404 Not Found for: {path}\n"
                f"- The file name must match exactly (including subfolders).\n"
                f"- If the repo is private, ensure you are authenticated (HF token in env).\n"
                f"- Error: {e}",
                file=sys.stderr,
            )
            sys.exit(1)
        except HfHubHTTPError as e:
            print(f"\nDownload failed: {e}", file=sys.stderr)
            sys.exit(1)
    return downloaded


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Download a .gguf model from a Hugging Face repo."
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

    variants = group_variants(files)
    print_menu(variants)
    idx = choose_index(len(variants))

    chosen = variants[idx]
    part_count = len(chosen["files"])
    size_str = human_size(chosen["total_size"] or None)
    print(
        f"You selected: {chosen['display']}  {size_str}"
        + (f"  ({part_count} parts)" if part_count > 1 else "")
    )

    downloaded = download_variant(repo_id, chosen, dest)

    if len(downloaded) == 1:
        print(f"Downloaded to {downloaded[0]}")
    else:
        print(f"Downloaded {len(downloaded)} parts to {dest}/")
        for p in downloaded:
            print(f"  {p}")


if __name__ == "__main__":
    main()
