#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qingtie-release.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

for architecture in arm64 x86_64; do
  options=(--configuration release --product QingTie --build-system native
    --scratch-path "$PROJECT_DIR/.build/release-$architecture"
    --triple "$architecture-apple-macosx14.0" --sdk "$SDK_PATH"
    -Xswiftc -file-prefix-map -Xswiftc "$PROJECT_DIR=.")
  swift build "${options[@]}"
  binary_dir="$(swift build "${options[@]}" --show-bin-path)"
  cp "$binary_dir/QingTie" "$WORK_DIR/QingTie-$architecture"
done

xcrun lipo -create "$WORK_DIR/QingTie-arm64" "$WORK_DIR/QingTie-x86_64" -output "$WORK_DIR/QingTie"
xcrun strip -S "$WORK_DIR/QingTie"
python3 scripts/package-app.py --executable "$WORK_DIR/QingTie"
codesign --force --sign - --timestamp=none dist/QingTie.app
codesign --verify --deep --strict --all-architectures --verbose=2 dist/QingTie.app
python3 scripts/check-package.py

mkdir "$WORK_DIR/image"
ditto --noextattr --norsrc --noqtn dist/QingTie.app "$WORK_DIR/image/QingTie.app"
ln -s /Applications "$WORK_DIR/image/Applications"
hdiutil create -ov -format UDZO -fs HFS+ -volname QingTie \
  -srcfolder "$WORK_DIR/image" dist/QingTie-universal.dmg
python3 - <<'PY'
from pathlib import Path
import hashlib
image = Path('dist/QingTie-universal.dmg')
digest = hashlib.sha256(image.read_bytes()).hexdigest()
Path('dist/SHA256SUMS.txt').write_text(f'{digest}  {image.name}\n')
PY
python3 scripts/check-release.py
printf 'Built: %s/dist/QingTie-universal.dmg\n' "$PROJECT_DIR"
