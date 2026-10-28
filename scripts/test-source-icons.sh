#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qingtie-source-icon-checks.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Read installed application metadata only. No clipboard, history, or app launches.
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -parse-as-library \
  "$PROJECT_DIR/Sources/QingTieApp/SourceApplicationIcon.swift" \
  "$PROJECT_DIR/Tests/SourceApplicationIconChecks.swift" \
  -o "$BUILD_DIR/SourceApplicationIconChecks"
"$BUILD_DIR/SourceApplicationIconChecks"
