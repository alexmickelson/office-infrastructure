#!/usr/bin/env nix-shell
#!nix-shell -i bash -p python3Packages.huggingface-hub

# ./download-huggingface.sh unsloth/gpt-oss-120b-GGUF

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <model-id> [dest-dir]" >&2
  exit 1
fi

MODEL_ID="$1"
DEST="${2:-./models}"

mkdir -p "$DEST"

echo "Fetching available .gguf files for $MODEL_ID ..."
MODELS=$(python3 - <<EOF
from huggingface_hub import list_repo_files
import re
from collections import defaultdict

files = list_repo_files("$MODEL_ID")
gguf_files = [f for f in files if f.endswith(".gguf")]

# Group files by model variant (handle multipart files)
models = defaultdict(list)
for f in gguf_files:
    # Check if it's a multipart file (e.g., model-Q4_K_M-00001-of-00002.gguf)
    multipart_match = re.match(r'(.+)-(\d{5})-of-(\d{5})\.gguf$', f)
    if multipart_match:
        base_name = multipart_match.group(1)
        models[base_name + ".gguf (multipart)"].append(f)
    else:
        models[f].append(f)

# Print model variants
for model_name in sorted(models.keys()):
    file_list = models[model_name]
    if len(file_list) > 1:
        print(f"{model_name}|{','.join(file_list)}")
    else:
        print(f"{model_name}|{file_list[0]}")
EOF
)

if [ -z "$MODELS" ]; then
  echo "No .gguf files found. Exiting."
  exit 1
fi

echo
echo "Available model variants:"
readarray -t model_options < <(echo "$MODELS" | cut -d'|' -f1)
readarray -t model_files < <(echo "$MODELS" | cut -d'|' -f2)

select choice in "${model_options[@]}"; do
  if [ -n "$choice" ]; then
    index=$((REPLY-1))
    selected_files="${model_files[$index]}"
    echo "You selected: $choice"
    
    if [[ "$selected_files" == *","* ]]; then
      # Multipart file - download all parts
      IFS=',' read -ra files_array <<< "$selected_files"
      echo "Downloading multipart model (${#files_array[@]} parts)..."
      for file in "${files_array[@]}"; do
        echo "Downloading part: $file"
        huggingface-cli download "$MODEL_ID" "$file" --local-dir "$DEST"
      done
      echo "All parts downloaded to $DEST/"
    else
      # Single file
      huggingface-cli download "$MODEL_ID" "$selected_files" --local-dir "$DEST"
      echo "Downloaded to $DEST/$selected_files"
    fi
    break
  else
    echo "Invalid choice."
  fi
done