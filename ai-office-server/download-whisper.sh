#!/bin/bash

# Download whisper.cpp models from Hugging Face
# Models will be saved to /data/models by default

MODEL_DIR="${1:-/data/models}"
BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

echo "Downloading Whisper models to: $MODEL_DIR"
mkdir -p "$MODEL_DIR"
cd "$MODEL_DIR" || exit 1

# Download different model sizes
# Comment out models you don't need

echo "Downloading tiny model (75 MB)..."
curl -L -o ggml-tiny.bin "$BASE_URL/ggml-tiny.bin"

echo "Downloading base model (142 MB)..."
curl -L -o ggml-base.bin "$BASE_URL/ggml-base.bin"

echo "Downloading small model (466 MB)..."
curl -L -o ggml-small.bin "$BASE_URL/ggml-small.bin"

# Uncomment to download larger models
# echo "Downloading medium model (1.5 GB)..."
# curl -L -o ggml-medium.bin "$BASE_URL/ggml-medium.bin"

# echo "Downloading large-v3 model (3.1 GB)..."
# curl -L -o ggml-large-v3.bin "$BASE_URL/ggml-large-v3.bin"

echo "Download complete!"
echo "Models available in: $MODEL_DIR"
ls -lh "$MODEL_DIR"/ggml-*.bin
