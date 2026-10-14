#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.artifacts/CheckDerivedData"

cd "$ROOT_DIR"
for tool in rg python3 node npm xcrun xcodebuild; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing developer prerequisite: $tool. See Docs/Developing.md." >&2
    exit 1
  fi
done
./Scripts/format.sh --lint
./Scripts/check_architecture.sh
python3 Scripts/release.py check
./Scripts/check_cli.sh
python3 -m unittest discover -s Scripts/tests
npm --prefix Packaging/npm test

npm --prefix Backend/Licensing ci
npm --prefix Backend/Licensing audit --audit-level=high
npm --prefix Backend/Licensing run check

xcodebuild -project PrimaryPaste.xcodeproj -scheme "Primary Paste" \
  -configuration Debug -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO build test

STRUCTURAL_ONLY=1 ./Scripts/phase6_verify.sh
