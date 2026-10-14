#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${APP_PATH:-/Applications/Primary Paste.app}"
EXPECTED_BUNDLE_ID="com.abel.primarypaste"
FAILURES=0
PASSES=0
WARNINGS=0

pass() { printf 'ok - %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf 'fail - %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
warn() { printf 'warn - %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }

printf 'Primary Paste preflight\n'
for path in \
  PrimaryPaste.xcodeproj/project.pbxproj \
  'PrimaryPaste.xcodeproj/xcshareddata/xcschemes/Primary Paste.xcscheme' \
  PrimaryPaste/Info.plist PrimaryPaste/PrimaryPaste.entitlements \
  PrimaryPaste/Assets.xcassets/AppIcon.appiconset/Contents.json \
  Docs/Architecture.md Docs/PhaseAudit.md Docs/Phase6Readiness.md \
  Backend/Licensing/migrations/0001_initial.sql Backend/Licensing/migrations/0002_payment_revocations.sql; do
  if [[ -f "$ROOT_DIR/$path" ]]; then pass "$path exists"; else fail "$path exists"; fi
done

if "$ROOT_DIR/Scripts/check_architecture.sh"; then pass "source ownership and privacy rules"; else fail "source ownership and privacy rules"; fi
for path in PrimaryPaste/Info.plist PrimaryPaste/PrimaryPaste.entitlements; do
  if plutil -lint "$ROOT_DIR/$path" >/dev/null; then pass "$path parses"; else fail "$path parses"; fi
done
if [[ -e "$ROOT_DIR/Package.swift" || -d "$ROOT_DIR/Sources/PrimaryPaste" ]]; then
  fail "one supported Xcode app target"
else
  pass "one supported Xcode app target"
fi

# Source-string matching cannot establish runtime behavior. Those invariants
# belong to XCTest, backend integration tests, and signed-app journey checks.
if [[ "${STRUCTURAL_ONLY:-0}" != "1" ]]; then
  printf '\nInstalled app: %s\n' "$APP_PATH"
  INFO_PLIST="$APP_PATH/Contents/Info.plist"
  if [[ -f "$INFO_PLIST" ]]; then
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)"
    scheme="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$INFO_PLIST" 2>/dev/null || true)"
    reason="$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$INFO_PLIST" 2>/dev/null || true)"
    if [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]]; then pass "installed bundle identity"; else fail "installed bundle identity"; fi
    if [[ -n "$executable" && -x "$APP_PATH/Contents/MacOS/$executable" ]]; then pass "installed executable"; else fail "installed executable"; fi
    if [[ "$scheme" == "primarypaste" ]]; then pass "setup and automation URL scheme"; else fail "setup and automation URL scheme"; fi
    if [[ -n "$reason" ]]; then pass "Finder Automation usage description"; else fail "Finder Automation usage description"; fi
  else
    fail "installed Info.plist"
  fi

  if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then pass "installed signature"; else fail "installed signature"; fi
  ENTITLEMENTS_FILE="$(mktemp)"
  trap 'rm -f "$ENTITLEMENTS_FILE"' EXIT
  if codesign -d --entitlements :- "$APP_PATH" >"$ENTITLEMENTS_FILE" 2>/dev/null; then
    automation="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.automation.apple-events' "$ENTITLEMENTS_FILE" 2>/dev/null || true)"
    if [[ "$automation" == "true" || "$automation" == "1" ]]; then pass "Finder Automation entitlement"; else fail "Finder Automation entitlement"; fi
  else
    fail "read installed entitlements"
  fi
  if pgrep -f "$APP_PATH/Contents/MacOS/Primary Paste" >/dev/null; then pass "installed app is running"; else warn "installed app is not running"; fi
  if [[ -n "${BUILT_APP_PATH:-}" ]]; then
    if cmp -s "$APP_PATH/Contents/MacOS/Primary Paste" "$BUILT_APP_PATH/Contents/MacOS/Primary Paste"; then
      pass "installed executable matches the verified build"
    else
      fail "installed executable matches the verified build"
    fi
  fi
  printf '\nReal-app selection, focus, privacy, and attachment journeys require the signed app.\n'
  printf 'Use Support → App Checks to record observed results; preflight does not mark them complete.\n'
fi

printf '\nPreflight: %d passed, %d warnings, %d failures\n' "$PASSES" "$WARNINGS" "$FAILURES"
[[ "$FAILURES" -eq 0 ]]
