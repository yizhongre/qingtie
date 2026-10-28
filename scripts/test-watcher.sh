#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d "${TMPDIR:-/tmp}/qingtie-watcher-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT
swiftc -swift-version 5 -parse-as-library Sources/QingTieCore/ClipboardRecord.swift Sources/QingTieCore/ClipboardCodec.swift Sources/QingTieCore/ClipboardWatcher.swift Tests/WatcherChecks.swift -o "$work/checks"
"$work/checks"
