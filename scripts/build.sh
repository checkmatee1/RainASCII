#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/bin"
TEMP_BINARY="$(mktemp "$ROOT/bin/.rain-ascii.XXXXXX")"
trap 'rm -f "$TEMP_BINARY"' EXIT
/usr/bin/xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" "$ROOT/Sources/main.swift" -framework AVFoundation -o "$TEMP_BINARY"
chmod +x "$TEMP_BINARY"
mv -f "$TEMP_BINARY" "$ROOT/bin/rain-ascii"
echo "已构建：$ROOT/bin/rain-ascii"
