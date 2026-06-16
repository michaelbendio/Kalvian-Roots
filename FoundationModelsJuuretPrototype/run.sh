#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
BINARY="$BUILD_DIR/juuret-foundation-models-demo"

mkdir -p "$BUILD_DIR"

xcrun swiftc \
  -parse-as-library \
  -framework FoundationModels \
  "$REPO_ROOT/Kalvian Roots/Models/Person.swift" \
  "$REPO_ROOT/Kalvian Roots/Models/Family.swift" \
  "$SCRIPT_DIR/Sources/JuuretFoundationModelsDemo/main.swift" \
  -o "$BINARY"

"$BINARY" "$@"
