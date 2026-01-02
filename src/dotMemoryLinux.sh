#!/usr/bin/env bash
set -euo pipefail

PID=1
SNAP_COUNT=3
SNAP_INTERVAL=60
OUT_DIR="/home/site/dotmemory"
URL="https://download.jetbrains.com/resharper/dotUltimate.2025.3.1/JetBrains.dotMemory.Console.linux-x64.2025.3.1.tar.gz"

mkdir -p "$OUT_DIR"

echo "Installing deps..."
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y curl ca-certificates tar gzip
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache curl ca-certificates tar gzip
else
  echo "No supported package manager"
  exit 1
fi

# Create ./dotmemory in the CURRENT PATH and use it
mkdir -p ./dotmemory
cd ./dotmemory

echo "Downloading dotMemory..."
curl -fsSL "$URL" -o dotmemory.tgz

echo "Extracting..."
tar -xzf dotmemory.tgz

echo "Locating dotmemory executable..."
DOTMEMORY="$(find . -maxdepth 3 -type f -name dotmemory | head -n 1)"

if [[ -z "$DOTMEMORY" ]]; then
  echo "ERROR: dotmemory binary not found"
  find . -maxdepth 2 -print
  exit 1
fi

# Ensure canonical ./dotmemory exists without self-copy
if [[ "$DOTMEMORY" != "./dotmemory" ]]; then
  cp -f "$DOTMEMORY" ./dotmemory
fi
chmod +x ./dotmemory

# ./dotmemory attach 1