#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FORMATTER="$(xcrun --find swift-format)"

if [[ "${1:-}" == "--lint" ]]; then
  "$FORMATTER" lint --strict --configuration "$ROOT_DIR/.swift-format" --recursive \
    "$ROOT_DIR/PrimaryPaste" "$ROOT_DIR/PrimaryPasteTests"
  "$FORMATTER" lint --strict --configuration "$ROOT_DIR/.swift-format" "$ROOT_DIR/Scripts/primary_paste_cli.swift" \
    "$ROOT_DIR/Scripts/qa_native_input.swift" "$ROOT_DIR/Scripts/qa_capture.swift"
else
  "$FORMATTER" format --in-place --configuration "$ROOT_DIR/.swift-format" --recursive \
    "$ROOT_DIR/PrimaryPaste" "$ROOT_DIR/PrimaryPasteTests"
  "$FORMATTER" format --in-place --configuration "$ROOT_DIR/.swift-format" "$ROOT_DIR/Scripts/primary_paste_cli.swift" \
    "$ROOT_DIR/Scripts/qa_native_input.swift" "$ROOT_DIR/Scripts/qa_capture.swift"
fi
