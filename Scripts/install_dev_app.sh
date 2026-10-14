#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/build/XcodeDerivedData}"
SOURCE_APP="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/Primary Paste.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALLED_APP="$INSTALL_DIR/Primary Paste.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
EXPECTED_BUNDLE_ID="com.abel.primarypaste"

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/package_app.sh"

mkdir -p "$INSTALL_DIR"
codesign --verify --deep --strict "$SOURCE_APP"
source_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")"
[[ "$source_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || { echo "Unexpected source app identity." >&2; exit 1; }

# Quit normally so pending clipboard operations can restore their snapshots.
# Never force-kill the app or delete the working installation before copying.
if pgrep -f "$INSTALLED_APP/Contents/MacOS/Primary Paste" >/dev/null; then
  osascript -e 'tell application id "com.abel.primarypaste" to quit'
  for attempt in {1..50}; do
    if ! pgrep -f "$INSTALLED_APP/Contents/MacOS/Primary Paste" >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -f "$INSTALLED_APP/Contents/MacOS/Primary Paste" >/dev/null; then
    echo "Primary Paste is still running. Quit it and retry the install." >&2
    exit 1
  fi
fi

STAGING_DIR="$(mktemp -d "$INSTALL_DIR/.primary-paste-install.XXXXXX")"
BACKUP_DIR="$ROOT_DIR/.artifacts/dev-install-backups/$(date +%Y%m%d-%H%M%S)"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$SOURCE_APP" "$STAGING_DIR/Primary Paste.app"
codesign --verify --deep --strict "$STAGING_DIR/Primary Paste.app"
if [[ -e "$INSTALLED_APP" ]]; then
  mkdir -p "$BACKUP_DIR"
  ditto "$INSTALLED_APP" "$BACKUP_DIR/Primary Paste.app"
  rm -rf "$INSTALLED_APP"
fi
if ! mv "$STAGING_DIR/Primary Paste.app" "$INSTALLED_APP"; then
  if [[ -d "$BACKUP_DIR/Primary Paste.app" ]]; then ditto "$BACKUP_DIR/Primary Paste.app" "$INSTALLED_APP"; fi
  echo "Installation failed; the previous app was restored." >&2
  exit 1
fi

if [[ -x "$LSREGISTER" ]]; then
  if command -v mdfind >/dev/null 2>&1; then
    while IFS= read -r app_path; do
      if [[ "$app_path" != "$INSTALLED_APP" ]]; then
        "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
      fi
    done < <(mdfind "kMDItemCFBundleIdentifier == '$EXPECTED_BUNDLE_ID'" 2>/dev/null || true)
  fi

  "$LSREGISTER" -u "$SOURCE_APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$ROOT_DIR/.build/app/PrimaryPaste.app" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$HOME/Applications/Primary Paste.app" >/dev/null 2>&1 || true
  "$LSREGISTER" -f -R -trusted "$INSTALLED_APP" >/dev/null 2>&1 || true
fi

if [[ "${OPEN_AFTER_INSTALL:-1}" == "1" ]]; then open "$INSTALLED_APP"; fi

echo "$INSTALLED_APP"
