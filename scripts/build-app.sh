#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
python3 scripts/package-app.py
codesign --force --deep --sign - dist/QingTie.app
codesign --verify --deep --strict --verbose=2 dist/QingTie.app
print "Built: $PWD/dist/QingTie.app"
