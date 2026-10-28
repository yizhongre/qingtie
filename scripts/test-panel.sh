#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qingtie-panel-checks.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
TARGET="$(uname -m)-apple-macosx14.0"

# Compile the core and UI using private pasteboards and temporary history.
xcrun swiftc -swift-version 5 -target "$TARGET" -parse-as-library \
  -emit-library -emit-module -module-name QingTieCore \
  -emit-module-path "$BUILD_DIR/QingTieCore.swiftmodule" \
  "$PROJECT_DIR/Sources/QingTieCore/ClipboardRecord.swift" \
  "$PROJECT_DIR/Sources/QingTieCore/ClipboardCodec.swift" \
  "$PROJECT_DIR/Sources/QingTieCore/ClipboardHistory.swift" \
  -o "$BUILD_DIR/libQingTieCore.dylib"

xcrun swiftc -swift-version 5 -target "$TARGET" -parse-as-library \
  -I "$BUILD_DIR" -L "$BUILD_DIR" -lQingTieCore \
  -Xlinker -rpath -Xlinker "$BUILD_DIR" \
  "$PROJECT_DIR/Sources/QingTieApp/QingTieTheme.swift" \
  "$PROJECT_DIR/Sources/QingTieApp/SourceApplicationIcon.swift" \
  "$PROJECT_DIR/Sources/QingTieApp/ClipboardPanelState.swift" \
  "$PROJECT_DIR/Sources/QingTieApp/ClipboardPanelView.swift" \
  "$PROJECT_DIR/Sources/QingTieApp/AboutWindow.swift" \
  "$PROJECT_DIR/Sources/QingTieApp/FilePreviewView.swift" \
  "$PROJECT_DIR/Tests/PanelStateChecks.swift" \
  -o "$BUILD_DIR/PanelStateChecks"

"$BUILD_DIR/PanelStateChecks"
