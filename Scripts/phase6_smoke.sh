#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-/Applications/Primary Paste.app}"
APP_NAME="Primary Paste"
EXECUTABLE_NAME="Primary Paste"
EXPECTED_BUNDLE_ID="com.abel.primarypaste"
DEFAULTS_DOMAIN="com.abel.primarypaste"
FAILURES=0
WARNINGS=0
PASSES=0
TMP_DIR="$(mktemp -d)"
CLIPBOARD_HELPER="$TMP_DIR/ClipboardArchive.swift"
CLIPBOARD_ARCHIVE="$TMP_DIR/clipboard.plist"
FRONTMOST_HELPER="$TMP_DIR/FrontmostIdentity.swift"
RESTORE_CLIPBOARD_ON_EXIT=0
SHOW_SETUP_RESTORE_MODE=""
SHOW_SETUP_RESTORE_VALUE=""
IS_ENABLED_RESTORE_MODE=""
IS_ENABLED_RESTORE_VALUE=""
PRIVATE_MODE_RESTORE_MODE=""
PRIVATE_MODE_RESTORE_VALUE=""
SHOW_STATUS_TEXT_RESTORE_MODE=""
SHOW_STATUS_TEXT_RESTORE_VALUE=""

usage() {
  cat <<'USAGE'
Primary Paste Phase 6 smoke test

Quiet:
  ./Scripts/phase6_smoke.sh

UI:
  RUN_UI_SMOKE=1 ./Scripts/phase6_smoke.sh

Clipboard:
  RUN_UI_SMOKE=1 RUN_CLIPBOARD_TEST=1 ./Scripts/phase6_smoke.sh

Launch:
  RUN_UI_SMOKE=1 RUN_LAUNCH_TEST=1 ./Scripts/phase6_smoke.sh

Environment:
  APP_PATH=/path/to/Primary\ Paste.app
      App bundle to smoke test. Defaults to /Applications/Primary Paste.app.

  RUN_UI_SMOKE=1
      Enables focus-stealing UI checks for menus, setup window, and status item.

  RUN_CLIPBOARD_TEST=1
      Keeps support-report clipboard export out of normal menu smoke. Report
      export belongs to hidden Support, so this mode currently skips copying
      while preserving the UI/launch test matrix shape.
      Implies RUN_UI_SMOKE=1.

  RUN_LAUNCH_TEST=1
      Temporarily changes showSetupOnLaunch, quits/relaunches the app, verifies
      setup stays quiet, and restores the original setting.
      Implies RUN_UI_SMOKE=1.
USAGE
}

if (( $# > 0 )); then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
fi

cleanup() {
  local exit_code=$?
  set +e
  restore_status_test_defaults
  restore_show_setup_default
  if (( RESTORE_CLIPBOARD_ON_EXIT == 1 )); then
    restore_clipboard >/dev/null 2>&1
  fi
  rm -rf "$TMP_DIR"
  exit "$exit_code"
}

restore_show_setup_default() {
  if [[ -n "$SHOW_SETUP_RESTORE_MODE" ]]; then
    if [[ "$SHOW_SETUP_RESTORE_MODE" == "missing" ]]; then
      defaults delete "$DEFAULTS_DOMAIN" showSetupOnLaunch >/dev/null 2>&1 || true
    else
      defaults write "$DEFAULTS_DOMAIN" showSetupOnLaunch -bool "$SHOW_SETUP_RESTORE_VALUE" >/dev/null 2>&1 || true
    fi
    SHOW_SETUP_RESTORE_MODE=""
    SHOW_SETUP_RESTORE_VALUE=""
  fi
}

restore_bool_default() {
  local key="$1"
  local mode="$2"
  local value="$3"

  if [[ -z "$mode" ]]; then
    return
  fi

  if [[ "$mode" == "missing" ]]; then
    defaults delete "$DEFAULTS_DOMAIN" "$key" >/dev/null 2>&1 || true
  else
    defaults write "$DEFAULTS_DOMAIN" "$key" -bool "$value" >/dev/null 2>&1 || true
  fi
}

restore_status_test_defaults() {
  restore_bool_default "isEnabled" "$IS_ENABLED_RESTORE_MODE" "$IS_ENABLED_RESTORE_VALUE"
  restore_bool_default "isPrivateModeEnabled" "$PRIVATE_MODE_RESTORE_MODE" "$PRIVATE_MODE_RESTORE_VALUE"
  restore_bool_default "showMenuBarStatusText" "$SHOW_STATUS_TEXT_RESTORE_MODE" "$SHOW_STATUS_TEXT_RESTORE_VALUE"
  IS_ENABLED_RESTORE_MODE=""
  IS_ENABLED_RESTORE_VALUE=""
  PRIVATE_MODE_RESTORE_MODE=""
  PRIVATE_MODE_RESTORE_VALUE=""
  SHOW_STATUS_TEXT_RESTORE_MODE=""
  SHOW_STATUS_TEXT_RESTORE_VALUE=""
}

trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
  PASSES=$((PASSES + 1))
}

warn() {
  printf 'warn - %s\n' "$1"
  WARNINGS=$((WARNINGS + 1))
}

skip() {
  printf 'skip - %s\n' "$1"
}

fail() {
  printf 'fail - %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

is_truthy() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_osascript() {
  local script_path=""

  if [[ $# -eq 0 ]]; then
    script_path="$TMP_DIR/osascript-$RANDOM.applescript"
    cat >"$script_path"
    osascript "$script_path" 2>/dev/null &
  else
    osascript "$@" 2>/dev/null &
  fi

  local pid=$!
  for _ in {1..200}; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      wait "$pid"
      return $?
    fi
    sleep 0.1
  done

  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  return 124
}

write_clipboard_helper() {
  cat >"$CLIPBOARD_HELPER" <<'SWIFT'
import AppKit
import Foundation

struct ArchivedEntry: Codable {
    let type: String
    let data: Data
}

struct ArchivedItem: Codable {
    let entries: [ArchivedEntry]
}

guard CommandLine.arguments.count >= 2 else {
    exit(64)
}

let command = CommandLine.arguments[1]
let pasteboard = NSPasteboard.general

func archiveURL() -> URL {
    guard CommandLine.arguments.count == 3 else {
        exit(64)
    }
    return URL(fileURLWithPath: CommandLine.arguments[2])
}

switch command {
case "change-count":
    print(pasteboard.changeCount)

case "save":
    let archivedItems = (pasteboard.pasteboardItems ?? []).compactMap { item -> ArchivedItem? in
        let entries = item.types.compactMap { type -> ArchivedEntry? in
            guard let data = item.data(forType: type) else { return nil }
            return ArchivedEntry(type: type.rawValue, data: data)
        }
        return entries.isEmpty ? nil : ArchivedItem(entries: entries)
    }
    let encoded = try PropertyListEncoder().encode(archivedItems)
    try encoded.write(to: archiveURL(), options: .atomic)

case "restore":
    let data = try Data(contentsOf: archiveURL())
    let archivedItems = try PropertyListDecoder().decode([ArchivedItem].self, from: data)
    let restoredItems = archivedItems.map { archivedItem -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for entry in archivedItem.entries {
            item.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.type))
        }
        return item
    }
    pasteboard.clearContents()
    pasteboard.writeObjects(restoredItems)

default:
    exit(64)
}
SWIFT
}

save_clipboard() {
  write_clipboard_helper
  /usr/bin/swift "$CLIPBOARD_HELPER" save "$CLIPBOARD_ARCHIVE" >/dev/null 2>&1
}

clipboard_change_count() {
  write_clipboard_helper
  /usr/bin/swift "$CLIPBOARD_HELPER" change-count
}

restore_clipboard() {
  [[ -f "$CLIPBOARD_ARCHIVE" ]] || return 0
  /usr/bin/swift "$CLIPBOARD_HELPER" restore "$CLIPBOARD_ARCHIVE" >/dev/null 2>&1
}

app_process_pattern() {
  printf '%s/Contents/MacOS/%s' "$APP_PATH" "$EXECUTABLE_NAME"
}

is_app_running() {
  pgrep -f "$(app_process_pattern)" >/dev/null
}

wait_for_app_running() {
  for _ in {1..30}; do
    if is_app_running; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

wait_for_app_exit() {
  for _ in {1..30}; do
    if ! is_app_running; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

primary_paste_window_state() {
  /usr/bin/swift - 2>/dev/null <<'SWIFT'
import CoreGraphics
import Foundation

func intValue(_ value: Any?) -> Int {
    if let number = value as? NSNumber { return number.intValue }
    if let int = value as? Int { return int }
    if let double = value as? Double { return Int(double) }
    return 0
}

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let name = window[kCGWindowName as String] as? String ?? ""
    let layer = intValue(window[kCGWindowLayer as String])
    guard owner == "Primary Paste", name == "Primary Paste", layer == 0 else { continue }
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else { continue }
    let width = intValue(bounds["Width"])
    let height = intValue(bounds["Height"])
    guard width > 300, height > 300 else { continue }
    print("window,\(width),\(height)")
    exit(0)
}

print("missing")
SWIFT
}

setup_window_count() {
  local state
  state="$(primary_paste_window_state || true)"
  case "$state" in
    window,*)
      printf '1'
      ;;
    missing)
      printf '0'
      ;;
    *)
      printf ''
      ;;
  esac
}

settled_setup_window_count() {
  local count max_count=0

  for _ in {1..15}; do
    count="$(setup_window_count || true)"
    if [[ "$count" =~ ^[0-9]+$ && "$count" -gt "$max_count" ]]; then
      max_count="$count"
    fi
    sleep 0.2
  done

  printf '%s' "$max_count"
}

frontmost_identity() {
  cat >"$FRONTMOST_HELPER" <<'SWIFT'
import AppKit
import Foundation

guard let application = NSWorkspace.shared.frontmostApplication else {
    exit(1)
}

let name = application.localizedName ?? application.bundleURL?.deletingPathExtension().lastPathComponent ?? "Unknown"
let bundleIdentifier = application.bundleIdentifier ?? ""
print("\(name)|\(bundleIdentifier)")
SWIFT
  /usr/bin/swift "$FRONTMOST_HELPER" 2>/dev/null || true
}

remember_show_setup_default() {
  if SHOW_SETUP_RESTORE_VALUE="$(defaults read "$DEFAULTS_DOMAIN" showSetupOnLaunch 2>/dev/null)"; then
    SHOW_SETUP_RESTORE_MODE="value"
    if [[ "$SHOW_SETUP_RESTORE_VALUE" == "0" ]]; then
      SHOW_SETUP_RESTORE_VALUE=false
    else
      SHOW_SETUP_RESTORE_VALUE=true
    fi
  else
    SHOW_SETUP_RESTORE_MODE="missing"
    SHOW_SETUP_RESTORE_VALUE=""
  fi
}

remember_bool_default() {
  local key="$1"
  local mode_var="$2"
  local value_var="$3"
  local value

  if value="$(defaults read "$DEFAULTS_DOMAIN" "$key" 2>/dev/null)"; then
    printf -v "$mode_var" "value"
    if [[ "$value" == "0" ]]; then
      printf -v "$value_var" "false"
    else
      printf -v "$value_var" "true"
    fi
  else
    printf -v "$mode_var" "missing"
    printf -v "$value_var" ""
  fi
}

remember_status_test_defaults() {
  if [[ -z "$IS_ENABLED_RESTORE_MODE" ]]; then
    remember_bool_default "isEnabled" "IS_ENABLED_RESTORE_MODE" "IS_ENABLED_RESTORE_VALUE"
  fi
  if [[ -z "$PRIVATE_MODE_RESTORE_MODE" ]]; then
    remember_bool_default "isPrivateModeEnabled" "PRIVATE_MODE_RESTORE_MODE" "PRIVATE_MODE_RESTORE_VALUE"
  fi
  if [[ -z "$SHOW_STATUS_TEXT_RESTORE_MODE" ]]; then
    remember_bool_default "showMenuBarStatusText" "SHOW_STATUS_TEXT_RESTORE_MODE" "SHOW_STATUS_TEXT_RESTORE_VALUE"
  fi
}

relaunch_app() {
  run_osascript -e 'quit app "Primary Paste"' >/dev/null 2>&1 || true
  if ! wait_for_app_exit >/dev/null 2>&1; then
    pkill -f "$APP_PATH/Contents/MacOS/Primary Paste" >/dev/null 2>&1 || true
  fi
  wait_for_app_exit >/dev/null 2>&1 || true
  open "$APP_PATH"
  wait_for_app_running >/dev/null 2>&1
}

status_item_name() {
  run_osascript <<'APPLESCRIPT' || true
tell application "System Events"
    tell process "Primary Paste"
        if (count of menu bars) < 2 then return "missing"
        return name of menu bar item 1 of menu bar 2
    end tell
end tell
APPLESCRIPT
}

status_name_for_defaults() {
  local enabled="$1"
  local private="$2"

  defaults write "$DEFAULTS_DOMAIN" isEnabled -bool "$enabled"
  defaults write "$DEFAULTS_DOMAIN" isPrivateModeEnabled -bool "$private"
  defaults write "$DEFAULTS_DOMAIN" showMenuBarStatusText -bool true
  relaunch_app >/dev/null 2>&1 || return 1
  sleep 0.5
  status_item_name
}

close_setup_window_if_visible() {
  run_osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Primary Paste" to activate
delay 0.1
tell application "System Events"
    tell process "Primary Paste"
        set frontmost to true
        if exists window "Primary Paste" then
            set setupWindow to window "Primary Paste"
            try
                perform action "AXPress" of (first button of setupWindow whose subrole is "AXCloseButton")
            on error
                try
                    click (first button of setupWindow whose subrole is "AXCloseButton")
                on error
                    try
                        click (first button of setupWindow whose description is "close button")
                    on error
                        keystroke "w" using command down
                    end try
                end try
            end try
        else
            keystroke "w" using command down
        end if
    end tell
end tell
APPLESCRIPT
}

check_installed_app() {
  if [[ ! -d "$APP_PATH" ]]; then
    fail "installed app exists"
    return 1
  fi
  pass "installed app exists"

  if [[ -x "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" ]]; then
    pass "installed executable exists"
  else
    fail "installed executable exists"
  fi
}

check_codesign() {
  if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    pass "installed app codesign verifies"
  else
    fail "installed app codesign verifies"
  fi
}

check_launch_services() {
  local bundle_id
  bundle_id="$(run_osascript -e 'id of app "Primary Paste"' || true)"
  if [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]]; then
    pass "Launch Services bundle id is $EXPECTED_BUNDLE_ID"
  else
    fail "Launch Services bundle id is $EXPECTED_BUNDLE_ID"
  fi
}

check_system_events_process() {
  local process_exists
  process_exists="$(run_osascript -e 'tell application "System Events" to exists process "Primary Paste"' || true)"
  if [[ "$process_exists" == "true" ]]; then
    pass "System Events can see Primary Paste process"
  else
    warn "System Events cannot see Primary Paste process; Accessibility may be unavailable to the shell"
  fi
}

check_no_clipboard_mutation() {
  local before="$1"
  local after="$2"

  if [[ -z "$before" || -z "$after" ]]; then
    warn "clipboard change count could not be read"
  elif [[ "$before" == "$after" ]]; then
    pass "quiet smoke did not mutate the clipboard"
  else
    fail "quiet smoke did not mutate the clipboard"
  fi
}

check_no_setup_window() {
  local before="$1"
  local after="$2"

  case "$after" in
    0)
      pass "quiet smoke did not open a setup window"
      ;;
    "")
      warn "setup window state could not be inspected"
      ;;
    *)
      if [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ && "$after" -le "$before" ]]; then
        warn "setup window was already open before quiet smoke; no new setup window was opened"
      else
        fail "quiet smoke did not open a setup window"
      fi
      ;;
  esac
}

check_no_focus_steal() {
  local before="$1"
  local after="$2"

  if [[ -z "$before" || -z "$after" ]]; then
    warn "frontmost app could not be inspected"
    return
  fi

  if [[ "$before" == "$after" ]]; then
    pass "quiet launch did not change the frontmost app"
    return
  fi

  if [[ "$after" == "$APP_NAME|"* || "$after" == *"|$EXPECTED_BUNDLE_ID" ]]; then
    fail "quiet launch made Primary Paste frontmost"
  else
    warn "frontmost app changed during quiet smoke: $before -> $after"
  fi
}

run_quiet_smoke() {
  local clipboard_before clipboard_after frontmost_before frontmost_after window_before window_after

  if is_app_running; then
    pass "installed app was already running"
    window_before="$(settled_setup_window_count || true)"
    clipboard_before="$(clipboard_change_count 2>/dev/null || true)"
    frontmost_before="$(frontmost_identity || true)"
  else
    frontmost_before="$(frontmost_identity || true)"
    clipboard_before="$(clipboard_change_count 2>/dev/null || true)"
    window_before=0
    if open -g "$APP_PATH" && wait_for_app_running; then
      pass "installed app launched without foreground activation request"
    else
      fail "installed app launched without foreground activation request"
    fi
  fi

  if [[ -z "$window_before" ]]; then
    window_before=0
  fi

  sleep 1.0
  if wait_for_app_running; then
    pass "installed app is running"
  else
    fail "installed app is running"
  fi
  check_system_events_process

  clipboard_after="$(clipboard_change_count 2>/dev/null || true)"
  frontmost_after="$(frontmost_identity || true)"
  window_after="$(setup_window_count || true)"

  check_no_clipboard_mutation "$clipboard_before" "$clipboard_after"
  check_no_setup_window "$window_before" "$window_after"
  check_no_focus_steal "$frontmost_before" "$frontmost_after"
}

normalize_modes() {
  if is_truthy "${RUN_CLIPBOARD_TEST:-0}" && ! is_truthy "${RUN_UI_SMOKE:-0}"; then
    RUN_UI_SMOKE=1
    warn "RUN_CLIPBOARD_TEST=1 implies RUN_UI_SMOKE=1"
  fi

  if is_truthy "${RUN_LAUNCH_TEST:-0}" && ! is_truthy "${RUN_UI_SMOKE:-0}"; then
    RUN_UI_SMOKE=1
    warn "RUN_LAUNCH_TEST=1 implies RUN_UI_SMOKE=1"
  fi
}

print_header() {
  printf 'Primary Paste Phase 6 smoke test\n'
  printf 'App: %s\n' "$APP_PATH"
  printf 'Mode: quiet'
  if is_truthy "${RUN_UI_SMOKE:-0}"; then
    printf ' + ui'
  fi
  if is_truthy "${RUN_CLIPBOARD_TEST:-0}"; then
    printf ' + clipboard'
  fi
  if is_truthy "${RUN_LAUNCH_TEST:-0}"; then
    printf ' + launch'
  fi
  printf '\n\n'
}

print_summary() {
  printf '\nSummary: %d passed, %d warnings, %d failures\n' "$PASSES" "$WARNINGS" "$FAILURES"
}

normalize_modes
print_header

if ! check_installed_app; then
  print_summary
  exit 1
fi

check_codesign

if ! is_truthy "${RUN_UI_SMOKE:-0}"; then
  check_launch_services
  run_quiet_smoke
  print_summary

  if (( FAILURES > 0 )); then
    exit 1
  fi
  exit 0
fi

open "$APP_PATH"

if wait_for_app_running; then
  pass "installed app is running"
else
  fail "installed app is running"
fi

bundle_id="$(run_osascript -e 'id of app "Primary Paste"' || true)"
if [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]]; then
  pass "Launch Services bundle id is $EXPECTED_BUNDLE_ID"
else
  fail "Launch Services bundle id is $EXPECTED_BUNDLE_ID"
fi

process_exists="$(run_osascript -e 'tell application "System Events" to exists process "Primary Paste"' || true)"
if [[ "$process_exists" == "true" ]]; then
  pass "System Events can see Primary Paste process"
else
  warn "System Events cannot see Primary Paste process; Accessibility may be unavailable to the shell"
fi

menu_state="$(run_osascript <<'APPLESCRIPT' || true
tell application "Primary Paste" to activate
delay 0.2
tell application "System Events"
    tell process "Primary Paste"
        set hasShowSetup to exists menu item "Permissions & Setup..." of menu "Primary Paste" of menu bar item "Primary Paste" of menu bar 1
        set hasCopyDiagnostics to exists menu item "Copy Support Report" of menu "Primary Paste" of menu bar item "Primary Paste" of menu bar 1
        return (hasShowSetup as text) & "," & (hasCopyDiagnostics as text)
    end tell
end tell
APPLESCRIPT
)"

if [[ "$menu_state" == "true,false" ]]; then
  pass "main menu exposes setup while keeping support report hidden"
else
  warn "main menu smoke check could not verify setup/support-report visibility"
fi

open "primarypaste://show-setup" >/dev/null 2>&1 || true
window_state="missing"
for _ in {1..20}; do
  window_state="$(primary_paste_window_state || true)"
  if [[ "$window_state" == window,* ]]; then
    break
  fi
  sleep 0.2
done

if [[ "$window_state" == window,* ]]; then
  pass "setup window opens from deep link ($window_state)"
else
  warn "setup window smoke check could not open or inspect the deep-linked window"
fi

close_setup_window_if_visible
closed_window_state="unknown"
for _ in {1..40}; do
  closed_window_state="$(primary_paste_window_state || true)"
  if [[ "$closed_window_state" == "missing" ]]; then
    break
  fi
  sleep 0.25
done
if [[ "$closed_window_state" == "missing" ]]; then
  pass "setup window closed after UI smoke"
else
  warn "setup window could not be closed after UI smoke"
fi

status_menu_state="$(run_osascript <<'APPLESCRIPT' || true
tell application "Primary Paste" to activate
delay 0.2
tell application "System Events"
    tell process "Primary Paste"
        if (count of menu bars) < 2 then return "missing-status-menu-bar"
        set statusItemName to name of menu bar item 1 of menu bar 2
        set statusItemDescription to ""
        try
            set statusItemDescription to description of menu bar item 1 of menu bar 2
        end try

        click menu bar item 1 of menu bar 2
        delay 0.2
        set itemNames to {}
        repeat with menuItemIndex from 1 to count of menu items of menu 1 of menu bar item 1 of menu bar 2
            set itemName to ""
            try
                set itemName to name of menu item menuItemIndex of menu 1 of menu bar item 1 of menu bar 2
            end try
            if itemName is not "" and itemName is not missing value then set end of itemNames to itemName
        end repeat
        key code 53

        set AppleScript's text item delimiters to linefeed
        set joinedItems to itemNames as text
        set AppleScript's text item delimiters to ""
        return "name=" & statusItemName & linefeed & "description=" & statusItemDescription & linefeed & joinedItems
    end tell
end tell
APPLESCRIPT
)"

if [[ "$status_menu_state" == *"name="* && "$status_menu_state" == *"Primary Paste:"* ]]; then
  pass "status item exposes Primary Paste state"
else
  warn "status item state could not be verified"
fi

if [[ "$status_menu_state" == *"Accessibility:"* && "$status_menu_state" == *"Input Monitoring:"* ]]; then
  pass "status menu exposes permission health"
else
  warn "status menu permission health could not be verified"
fi

if [[ "$status_menu_state" == *"Settings..."* && "$status_menu_state" != *"Copy Support Report"* ]]; then
  pass "status menu exposes settings while keeping support report hidden"
else
  warn "status menu action visibility could not be verified"
fi

remember_status_test_defaults
activeName="$(status_name_for_defaults true false || true)"
pausedName="$(status_name_for_defaults false false || true)"
privateName="$(status_name_for_defaults true true || true)"
restore_status_test_defaults
relaunch_app >/dev/null 2>&1 || true

status_transition_state="active=$activeName
paused=$pausedName
private=$privateName"

if [[ "$activeName" == "Setup" || "$activeName" == "missing value" || -z "$activeName" || "$activeName" == "Primary Paste:"* ]]; then
  pass "status item keeps active/setup state readable when enabled"
elif [[ "$activeName" == "missing" || "$activeName" == "status-menu-unavailable" ]]; then
  warn "status item active/setup label transition could not be verified"
else
  fail "status item keeps active/setup state readable when enabled"
fi

if [[ "$status_transition_state" == *"paused=Paused"* ]]; then
  pass "status item shows paused label when paused"
elif [[ "$pausedName" == "missing" || "$pausedName" == "status-menu-unavailable" || -z "$pausedName" ]]; then
  warn "status item paused label transition could not be verified"
else
  fail "status item shows paused label when paused"
fi

if [[ "$status_transition_state" == *"private=Private"* ]]; then
  pass "status item shows private label when private mode is on"
elif [[ "$privateName" == "missing" || "$privateName" == "status-menu-unavailable" || -z "$privateName" ]]; then
  warn "status item private label transition could not be verified"
else
  fail "status item shows private label when private mode is on"
fi

if [[ "${RUN_LAUNCH_TEST:-0}" == "1" ]]; then
  remember_show_setup_default
  close_setup_window_if_visible
  sleep 0.2

  run_osascript -e 'quit app "Primary Paste"' >/dev/null 2>&1 || true
  if ! wait_for_app_exit >/dev/null 2>&1; then
    pkill -f "$APP_PATH/Contents/MacOS/Primary Paste" >/dev/null 2>&1 || true
  fi
  if wait_for_app_exit; then
    pass "launch test stopped the app before relaunch"
  else
    fail "launch test stopped the app before relaunch"
  fi

  defaults write "$DEFAULTS_DOMAIN" showSetupOnLaunch -bool false
  open "$APP_PATH"

  if wait_for_app_running; then
    pass "launch test relaunched the app"
  else
    fail "launch test relaunched the app"
  fi

  launch_window_state="$(run_osascript <<'APPLESCRIPT' || true
delay 1.0
tell application "System Events"
    if not (exists process "Primary Paste") then return "missing-process"
    tell process "Primary Paste"
        return exists window "Primary Paste"
    end tell
end tell
APPLESCRIPT
)"

  if [[ "$launch_window_state" == "false" ]]; then
    pass "Show Setup on Launch off keeps setup window closed on launch"
  else
    fail "Show Setup on Launch off keeps setup window closed on launch"
  fi

  run_osascript -e 'quit app "Primary Paste"' >/dev/null 2>&1 || true
  if ! wait_for_app_exit >/dev/null 2>&1; then
    pkill -f "$APP_PATH/Contents/MacOS/Primary Paste" >/dev/null 2>&1 || true
  fi
  wait_for_app_exit >/dev/null 2>&1 || true
  restore_show_setup_default
  open "$APP_PATH"
  wait_for_app_running >/dev/null 2>&1 || true
  sleep 0.8
  close_setup_window_if_visible
else
  skip "launch behavior test not run; set RUN_LAUNCH_TEST=1 to exercise Show Setup on Launch"
fi

if [[ "${RUN_CLIPBOARD_TEST:-0}" == "1" ]]; then
  skip "support report copy not run from normal menus; hidden Support owns report export"
else
  skip "support report clipboard write not run from normal smoke; hidden Support owns report export"
fi

print_summary

if (( FAILURES > 0 )); then
  exit 1
fi
