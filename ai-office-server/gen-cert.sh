#!/usr/bin/env bash
set -e

OUT_DIR="/data/whisper-certs"
mkdir -p "$OUT_DIR"

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout "$OUT_DIR/whisper.key" \
  -out    "$OUT_DIR/whisper.crt" \
  -subj   "/CN=ai-office-server" \
  -addext "subjectAltName=DNS:ai-office-server,DNS:localhost,IP:127.0.0.1"

echo "Done. Cert in $OUT_DIR/whisper.crt"
