#!/usr/bin/env nix-shell
#!nix-shell -i bash -p python3Packages.huggingface-hub

# ./download-hf.sh unsloth/gpt-oss-120b-GGUF

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <model-id> [dest-dir]" >&2
  exit 1
fi

MODEL_ID="$1"
DEST="${2:-./models}"

mkdir -p "$DEST"

echo "Fetching available .gguf files for $MODEL_ID ..."
FILES=$(python3 - <<EOF
from huggingface_hub import list_repo_files
files = list_repo_files("$MODEL_ID")
for f in files:
    if f.endswith(".gguf"):
        print(f)
EOF
)

if [ -z "$FILES" ]; then
  echo "No .gguf files found. Exiting."
  exit 1
fi

echo
echo "Available model variants:"
select FILE in $FILES; do
  if [ -n "$FILE" ]; then
    echo "You selected: $FILE"
    huggingface-cli download "$MODEL_ID" "$FILE" --local-dir "$DEST"
    echo "Downloaded to $DEST/$FILE"
    break
  else
    echo "Invalid choice."
  fi
done