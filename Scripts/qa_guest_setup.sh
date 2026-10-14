#!/bin/bash
# Run manually inside the disposable macOS guest after reviewing the VM guide.
set -euo pipefail

if [[ "$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null || true)" != "1" ]]; then
  echo "This setup only runs inside a virtual machine; nothing was changed." >&2
  exit 1
fi

TRANSFER="$(cd "$(dirname "$0")" && pwd)"
GUEST_ROOT="$HOME/Library/Application Support/Primary Paste QA Guest"
[[ -f "$TRANSFER/Primary Paste.zip" && -f "$TRANSFER/host-test-key.pub"
  && -d "$TRANSFER/Primary Paste QA Helper.app" ]] || {
  echo "Run the copy in the mounted QA Share folder." >&2; exit 1;
}
[[ ! -e "$GUEST_ROOT" && ! -e "/Applications/Primary Paste.app" ]] || {
  echo "Guest setup already exists. Preserve it and use the host reset command." >&2; exit 1;
}

mkdir -m 700 -p "$GUEST_ROOT"
/usr/bin/ditto -x -k "$TRANSFER/Primary Paste.zip" "$GUEST_ROOT/Stage"
/usr/bin/codesign --verify --deep --strict "$GUEST_ROOT/Stage/Primary Paste.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$GUEST_ROOT/Stage/Primary Paste.app/Contents/Info.plist")" == "com.abel.primarypaste" ]]
/usr/bin/ditto "$GUEST_ROOT/Stage/Primary Paste.app" "/Applications/Primary Paste.app"
/usr/bin/codesign --verify --deep --strict "$TRANSFER/Primary Paste QA Helper.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TRANSFER/Primary Paste QA Helper.app/Contents/Info.plist")" == "com.abel.primarypaste.qa-helper" ]]
/usr/bin/ditto "$TRANSFER/Primary Paste QA Helper.app" "$GUEST_ROOT/Primary Paste QA Helper.app"
rm -rf "$GUEST_ROOT/Stage"
cp "$TRANSFER/native-input" "$GUEST_ROOT/native-input"
cp "$TRANSFER/first-paste.html" "$TRANSFER/app-checks.html" "$GUEST_ROOT/"
mkdir -m 700 -p "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
KEY="$(cat "$TRANSFER/host-test-key.pub")"
if ! /usr/bin/grep -Fqx "$KEY" "$HOME/.ssh/authorized_keys"; then
  printf '%s\n' "$KEY" >> "$HOME/.ssh/authorized_keys"
fi
printf '{"owner":"primary-paste-qa-guest","schema":1}\n' > "$GUEST_ROOT/ownership.json"
# A guest-only allowance keeps normal shutdown usable before desktop login.
# It permits this exact command, with no stored credential or general sudo grant.
POLICY="$GUEST_ROOT/shutdown-policy"
trap 'rm -f "$POLICY"' EXIT
printf '%s ALL=(root) NOPASSWD: /sbin/shutdown -h now\n' "$(id -un)" > "$POLICY"
/usr/sbin/visudo -cf "$POLICY"
sudo /usr/bin/install -o root -g wheel -m 440 "$POLICY" /etc/sudoers.d/primary-paste-qa
rm -f "$POLICY"
/usr/bin/open "/Applications/Primary Paste.app"
echo "Guest files prepared. Enable Remote Login for this QA user only in System Settings."
echo "Guest user: $(id -un)"
echo "Guest IP: $(/usr/sbin/ipconfig getifaddr en0 || true)"
echo "SSH host-key fingerprints (compare these before first connection):"
for key in /etc/ssh/ssh_host_*_key.pub; do
  [[ ! -f "$key" ]] || /usr/bin/ssh-keygen -lf "$key"
done
