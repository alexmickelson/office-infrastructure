#!/usr/bin/env bash

# Download whisper.cpp models from Hugging Face
# Models will be saved to /data/models by default

MODEL_DIR="${1:-/data/models}"
BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

echo "Downloading Whisper models to: $MODEL_DIR"
mkdir -p "$MODEL_DIR"
cd "$MODEL_DIR" || exit 1

download() {
  local file="$1"
  if [ -f "$file" ]; then
    echo "Skipping $file (already exists)"
  else
    echo "Downloading $file..."
    curl -L -o "$file" "$BASE_URL/$file"
  fi
}

# Download different model sizes
# Comment out models you don't need

download ggml-tiny.bin
download ggml-base.bin
download ggml-small.bin

# Uncomment to download larger models
# download ggml-medium.bin

download ggml-large-v3.bin

echo "Download complete!"
echo "Models available in: $MODEL_DIR"
ls -lh "$MODEL_DIR"/ggml-*.bin
