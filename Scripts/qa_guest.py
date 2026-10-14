#!/usr/bin/env python3
"""Run the scoped QA helper in the guest's GUI session over SSH, without host input."""
import argparse
import ipaddress
import re
import shlex
import subprocess
import sys
import uuid

from qa_vm import ROOT, load


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--shell", action="store_true", help="Run one command in the verified disposable guest")
    modes.add_argument("--relaunch", action="store_true", help="Restart the installed guest app between idle test runs")
    parser.add_argument("arguments", nargs="*", help="Guest helper arguments: permissions, clipboard, BUNDLE inspect/drag/middle/frame")
    args = parser.parse_args()
    manifest = load()
    guest = manifest.get("guest", {})
    user = guest.get("user", "")
    host = guest.get("host", "")
    if not re.fullmatch(r"[a-z_][a-z0-9_-]*", user) or not ipaddress.ip_address(host).is_private:
        raise RuntimeError("Record the verified disposable guest account and private IP in the VM manifest")
    keys = ROOT / "Keys"
    if not (keys / "known_hosts").is_file() or not (keys / "guest_ed25519").is_file():
        raise RuntimeError("Verified guest SSH credentials are missing")
    if args.shell and len(args.arguments) != 1:
        parser.error("--shell requires one quoted command")
    if args.relaunch and args.arguments:
        parser.error("--relaunch takes no helper arguments")
    if not args.shell and not args.relaunch and not args.arguments:
        parser.error("Supply helper arguments or --relaunch")
    token = uuid.uuid4().hex
    arguments = " ".join(shlex.quote(value) for value in args.arguments)
    # LaunchServices gives the helper its approved app identity and guest GUI session.
    # Running its executable directly under sshd does not inherit the GUI app's AX grant.
    command = f'''r="$HOME/Library/Application Support/Primary Paste QA Guest"
out="$r/{token}.out"; err="$r/{token}.err"
trap 'rm -f "$out" "$err"' EXIT
open -n -g -W -o "$out" --stderr "$err" "$r/Primary Paste QA Helper.app" --args {arguments} >/dev/null 2>&1 || exit
for attempt in $(seq 1 60); do
  if test -s "$out" || test -s "$err"; then break; fi
  sleep 0.05
done
if test -s "$err"; then cat "$err" >&2; exit 1; fi
if ! test -s "$out"; then echo "Guest helper produced no result" >&2; exit 1; fi
cat "$out"
'''
    if args.shell or args.relaunch:
        command = '''test "$(sysctl -n kern.hv_vmm_present)" = 1 || exit 1
r="$HOME/Library/Application Support/Primary Paste QA Guest"
test "$(plutil -extract owner raw "$r/ownership.json")" = primary-paste-qa-guest || exit 1
''' + (args.arguments[0] if args.shell else '''
# Only between tests: allow temporary clipboard transports to finish first.
sleep 1
pkill -TERM -x "Primary Paste" || true
for attempt in $(seq 1 80); do
  if ! pgrep -x "Primary Paste" >/dev/null; then break; fi
  sleep 0.1
done
if pgrep -x "Primary Paste" >/dev/null; then echo "Guest app did not exit; no force kill sent" >&2; exit 1; fi
codesign --verify --deep --strict "/Applications/Primary Paste.app" || exit
open -g "/Applications/Primary Paste.app" || exit
sleep 1
pgrep -x "Primary Paste" || exit 1
shasum -a 256 "/Applications/Primary Paste.app/Contents/MacOS/Primary Paste"
''')
    result = subprocess.run([
        "ssh", "-i", str(keys / "guest_ed25519"), "-o", "IdentitiesOnly=yes",
        "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
        "-o", 'UserKnownHostsFile="' + str(keys / "known_hosts") + '"',
        "-o", "StrictHostKeyChecking=yes", user + "@" + host, command,
    ], timeout=30)
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
