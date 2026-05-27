#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

IS_MMPROJ = re.compile(r"mmproj", re.IGNORECASE)
IS_INCOMPLETE = re.compile(r"\.part-\d+$|\.incomplete$|\.tmp$", re.IGNORECASE)

LLAMACPP_DEFAULTS = {
    "jinja": "on",
    "ctx-size": "0",
    "temp": "0.6",
    "top-p": "0.95",
    "top-k": "20",
    "min-p": "0.00",
}


@dataclass
class ModelEntry:
    section: str
    model_path: Path
    mmproj_path: Path | None


def strip_gguf_suffix(name: str) -> str:
    return re.sub(r"-gguf$", "", name, flags=re.IGNORECASE)


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def strip_shared_prefix(filename_stem: str, dir_name: str) -> str:
    result = filename_stem.lower()
    for part in re.split(r"[-_]", dir_name.lower()):
        result = re.sub(rf"^{re.escape(part)}[-_]?", "", result)
    return result


def derive_section_name(model_dir: Path, gguf_filename: str) -> str:
    dir_base = strip_gguf_suffix(model_dir.name)
    stem = Path(gguf_filename).stem
    unique_suffix = strip_shared_prefix(stem, dir_base)
    return (
        slugify(f"{dir_base}-{unique_suffix}") if unique_suffix else slugify(dir_base)
    )


def pick_best_mmproj(candidates: list[Path]) -> Path:
    for candidate in candidates:
        if "F16" in candidate.name:
            return candidate
    return candidates[0]


def group_ggufs_by_directory(models_root: Path) -> dict[Path, list[Path]]:
    groups: dict[Path, list[Path]] = {}
    for gguf_path in sorted(models_root.rglob("*.gguf")):
        if IS_INCOMPLETE.search(gguf_path.name):
            continue
        groups.setdefault(gguf_path.parent, []).append(gguf_path)
    return groups


def build_model_entries(cache_root: Path) -> list[ModelEntry]:
    models_root = cache_root / "models"
    if not models_root.is_dir():
        print(f"ERROR: {models_root} does not exist.", file=sys.stderr)
        sys.exit(1)

    entries = []
    for model_dir, gguf_files in sorted(group_ggufs_by_directory(models_root).items()):
        mmproj_files = [f for f in gguf_files if IS_MMPROJ.search(f.name)]
        main_files = [f for f in gguf_files if not IS_MMPROJ.search(f.name)]
        mmproj = pick_best_mmproj(mmproj_files) if mmproj_files else None

        for model_file in main_files:
            entries.append(
                ModelEntry(
                    section=derive_section_name(model_dir, model_file.name),
                    model_path=model_file,
                    mmproj_path=mmproj,
                )
            )

    return entries


def rebase_to_mount(path: Path, cache_root: Path, mount_path: str) -> str:
    return str(Path(mount_path) / path.relative_to(cache_root))


def render_section(
    entry: ModelEntry, cache_root: Path, mount_path: str | None
) -> list[str]:
    def path_str(path: Path) -> str:
        return (
            rebase_to_mount(path, cache_root, mount_path) if mount_path else str(path)
        )

    lines = [f"[{entry.section}]", f"model = {path_str(entry.model_path)}"]
    if entry.mmproj_path:
        lines.append(f"mmproj = {path_str(entry.mmproj_path)}")
    for key, value in LLAMACPP_DEFAULTS.items():
        lines.append(f"{key} = {value}")
    lines.append("")
    return lines


def render_config(
    entries: list[ModelEntry], cache_root: Path, mount_path: str | None
) -> str:
    header = [
        "; https://huggingface.co/blog/ggml-org/model-management-in-llamacpp",
        "",
    ]
    body = []
    for entry in entries:
        body.extend(render_section(entry, cache_root, mount_path))
    return "\n".join(header + body)


def print_discovered_entries(entries: list[ModelEntry]) -> None:
    print(f"Found {len(entries)} model(s):", file=sys.stderr)
    for entry in entries:
        mmproj_note = (
            f" (mmproj: {entry.mmproj_path.name})" if entry.mmproj_path else ""
        )
        print(
            f"  [{entry.section}] {entry.model_path.name}{mmproj_note}", file=sys.stderr
        )


class ArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_help(sys.stderr)
        self.exit(2, f"\nerror: {message}\n")


def parse_args() -> argparse.Namespace:
    parser = ArgumentParser(
        epilog=(
            "Example:\n"
            "  ./gen_config.py /data/huggingface-cache"
            " --container-cache-dir /root/.cache/huggingface/huggingface"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "host_cache_dir",
        metavar="host_cache_dir",
        help="HuggingFace cache root on the host  (e.g. /data/huggingface-cache)",
    )
    parser.add_argument(
        "--container-cache-dir",
        default=None,
        metavar="PATH",
        help=(
            "Path where host_cache_dir is mounted inside the container; rewrites all paths in the output  "
            "(e.g. /root/.cache/huggingface/huggingface)"
        ),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    cache_root = Path(args.host_cache_dir).resolve()
    mount_path = (
        args.container_cache_dir.rstrip("/") if args.container_cache_dir else None
    )

    if not cache_root.is_dir():
        print(f"ERROR: {cache_root} is not a directory.", file=sys.stderr)
        sys.exit(1)

    entries = build_model_entries(cache_root)
    if not entries:
        print("No GGUF model files found.", file=sys.stderr)
        sys.exit(1)

    print_discovered_entries(entries)
    print(render_config(entries, cache_root, mount_path))


if __name__ == "__main__":
    main()
