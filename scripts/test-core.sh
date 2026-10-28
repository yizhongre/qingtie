#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qingtie-core-checks.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -parse-as-library \
  "$PROJECT_DIR/Sources/QingTieCore/ClipboardRecord.swift" \
  "$PROJECT_DIR/Sources/QingTieCore/ClipboardCodec.swift" \
  "$PROJECT_DIR/Sources/QingTieCore/ClipboardHistory.swift" \
  "$PROJECT_DIR/Tests/CoreChecks.swift" \
  -o "$BUILD_DIR/CoreChecks"
"$BUILD_DIR/CoreChecks"
