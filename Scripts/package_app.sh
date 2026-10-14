#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/build/XcodeDerivedData}"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

cd "$ROOT_DIR"
swift "$ROOT_DIR/Scripts/generate_app_icon.swift"

# Permit another developer's identity without editing the checked-in project.
BUILD_ARGS=(
  -project "$ROOT_DIR/PrimaryPaste.xcodeproj"
  -scheme "Primary Paste"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_DIR"
)
if [[ ${DEVELOPMENT_TEAM+x} ]]; then BUILD_ARGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"); fi
if [[ ${CODE_SIGN_IDENTITY+x} ]]; then BUILD_ARGS+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY"); fi
if [[ ${CODE_SIGN_STYLE+x} ]]; then BUILD_ARGS+=("CODE_SIGN_STYLE=$CODE_SIGN_STYLE"); fi

xcodebuild "${BUILD_ARGS[@]}" build

echo "$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/Primary Paste.app"
