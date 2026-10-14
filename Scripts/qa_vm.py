#!/usr/bin/env python3
"""Lifecycle of the disposable Primary Paste macOS acceptance VM."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path.home() / "Library/Application Support/Primary Paste QA"
PATTERNS = (
    "Library/Containers/com.utmapp.UTM",
    "Library/Containers/com.utmapp.utmctl",
    "Library/Group Containers/WDNLXAD4W8.com.utmapp.UTM",
    "Library/Application Scripts/WDNLXAD4W8.com.utmapp.UTM",
    "Library/Application Scripts/com.utmapp.UTM",
    "Library/Application Scripts/com.utmapp.utmctl",
    "Library/Preferences/com.utmapp.UTM.plist",
    "Library/Preferences/com.utmapp.utmctl.plist",
    "Library/Saved Application State/com.utmapp.UTM.savedState",
    "Library/Caches/com.utmapp.UTM",
    "Library/Caches/com.utmapp.utmctl",
)


def load(root=None):
    root = ROOT if root is None else root
    if root.is_symlink():
        raise RuntimeError("Managed root must not be a symbolic link")
    manifest = json.loads((root / "manifest.json").read_text())
    if manifest.get("owner") != "primary-paste-qa" or manifest.get("schema") != 1:
        raise RuntimeError("Missing or incompatible ownership manifest")
    if Path(manifest["root"]).resolve() != root.resolve():
        raise RuntimeError("Ownership manifest does not match this folder")
    return manifest


def save(manifest):
    temporary = ROOT / "manifest.json.tmp"
    temporary.write_text(json.dumps(manifest, indent=2) + "\n")
    temporary.replace(ROOT / "manifest.json")


def external_paths():
    return sorted({str(p) for pattern in PATTERNS for p in Path.home().glob(pattern)})


def refresh_owned(manifest):
    before = set(manifest["externalPathsBefore"])
    manifest["externalPathsCreated"] = [p for p in external_paths() if p not in before]
    save(manifest)


def cli(manifest, command, *arguments):
    if manifest.get("runner") == "headless":
        import qa_headless
        expected = identity(manifest)
        if command in {"status", "start", "delete"} and arguments != (expected,):
            raise RuntimeError("Headless commands must name exactly the owned guest")
        if command == "stop" and arguments != (expected, "--request"):
            raise RuntimeError("Only orderly shutdown of the owned guest is supported")
        if command == "list" and arguments:
            raise RuntimeError("Guest registry inspection takes no arguments")
        if command == "status":
            return qa_headless.status(manifest)
        if command == "start":
            qa_headless.start(manifest)
            return ""
        if command == "stop" and arguments[-1:] == ("--request",):
            qa_headless.request_stop(manifest)
            return ""
        if command == "list":
            return qa_headless.registered(manifest)
        if command == "delete":
            qa_headless.unregister_owned(manifest)
            return ""
        raise RuntimeError("Unsupported headless guest command")
    tool = ROOT / "Tools/UTM.app/Contents/MacOS/utmctl"
    if not tool.is_file():
        raise RuntimeError("Managed UTM installation is missing")
    result = subprocess.run([str(tool), command, "--hide", *arguments],
                            text=True, capture_output=True, timeout=45)
    if result.returncode or "Error from event:" in result.stderr:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "UTM command failed")
    return result.stdout.strip()


def identity(manifest):
    value = manifest.get("vmUUID", "")
    if not re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", value):
        raise RuntimeError("VM creation is not complete; no managed VM UUID has been recorded")
    return value


def require_stopped(manifest):
    state = cli(manifest, "status", identity(manifest)).lower()
    if state != "stopped":
        raise RuntimeError(f"VM must be stopped before this operation (reported: {state})")


def package(manifest):
    path = Path(manifest["vmPath"])
    parent = ROOT / "VM"
    if parent.is_symlink() or path.parent != parent or path.is_symlink():
        raise RuntimeError("VM package is outside the managed folder")
    return path


def validate_package(manifest, vm=None):
    vm = package(manifest) if vm is None else vm
    if vm.is_symlink() or vm.parent not in (ROOT, ROOT / "VM") or not vm.is_dir():
        raise RuntimeError("VM package is outside the managed folder or missing")
    if (vm / "config.plist").is_symlink():
        raise RuntimeError("VM configuration must not be a symbolic link")
    config = plistlib.loads((vm / "config.plist").read_bytes())
    if config["Information"]["UUID"].lower() != identity(manifest).lower():
        raise RuntimeError("VM package identity does not match its ownership record")
    if config.get("Backend") != "Apple" or config.get("Virtualization", {}).get("ClipboardSharing", True):
        raise RuntimeError("VM must use Apple virtualization with clipboard sharing disabled")


def clone(source, destination):
    if destination.exists() or destination.is_symlink():
        raise RuntimeError(f"Destination already exists: {destination}")
    # APFS clones avoid a second physical copy of a large virtual disk.
    subprocess.run(["/bin/cp", "-cR", str(source), str(destination)], check=True)
    if not (destination / "config.plist").is_file():
        raise RuntimeError("Copied VM package is incomplete")


def stop(manifest):
    uuid = identity(manifest)
    if cli(manifest, "status", uuid).lower() == "stopped":
        return
    # Use the guest's narrowly allowed shutdown command, including at login.
    # The Apple VM's power-button request needs a guest confirmation dialog.
    guest = manifest.get("guest", {})
    if guest.get("host") and guest.get("user") and (ROOT / "Keys/guest_ed25519").is_file():
        try:
            result = subprocess.run([
                sys.executable, str(Path(__file__).with_name("qa_guest.py")), "--shell",
                "sleep 1; sudo -n /sbin/shutdown -h now",
            ], text=True, capture_output=True, timeout=35)
            requested = result.returncode == 0
        except subprocess.SubprocessError:
            requested = False
    else:
        requested = False
    if cli(manifest, "status", uuid).lower() == "stopped":
        return
    if not requested:
        cli(manifest, "stop", uuid, "--request")
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if cli(manifest, "status", uuid).lower() == "stopped":
            return
        time.sleep(2)
    raise RuntimeError("Guest did not shut down. Stop it normally in UTM, then retry; no force kill was sent")


def terminate_owned_utm():
    executable = ROOT / "Tools/UTM.app/Contents/MacOS/UTM"
    result = subprocess.run(["pgrep", "-f", "^" + re.escape(str(executable)) + "$"],
                            text=True, capture_output=True)
    pids = [int(p) for p in result.stdout.split()]
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        alive = []
        for pid in pids:
            try:
                os.kill(pid, 0)
                alive.append(pid)
            except ProcessLookupError:
                pass
        if not alive:
            return
        time.sleep(0.2)
    raise RuntimeError("UTM has not exited; files were preserved")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["status", "up", "down", "baseline", "reset", "teardown"])
    parser.add_argument("--preview", action="store_true", help="Show teardown scope without changing anything")
    parser.add_argument("--headless", action="store_true", help="Start the existing guest without host windows or Apple Events")
    args = parser.parse_args()
    manifest = load()
    if args.headless:
        if args.action != "up":
            parser.error("--headless is only available for up; subsequent commands use the saved runner choice")
        validate_package(manifest)
        import qa_headless
        if not qa_headless.process(manifest):
            qa_headless.require_idle_storage(manifest)
        manifest["runner"] = "headless"
        save(manifest)
    if args.preview and args.action != "teardown":
        parser.error("--preview is only available for teardown")
    if not args.preview and args.action != "status":
        refresh_owned(manifest)
    vm = package(manifest)
    if args.action == "status":
        output = {k: manifest.get(k) for k in ["root", "vmPath", "vmUUID", "cpus", "memoryMiB", "diskGiB", "clipboardSharing", "runner"]}
        output["baselineReady"] = (ROOT / "Baseline.utm/config.plist").is_file()
        output["state"] = cli(manifest, "status", identity(manifest)) if manifest.get("vmUUID") else "not yet created"
        print(json.dumps(output, indent=2))
    elif args.action == "up":
        validate_package(manifest)
        if cli(manifest, "status", identity(manifest)).lower() == "started":
            print("Managed VM is already running")
        else:
            cli(manifest, "start", identity(manifest))
            print("Started the managed VM; host clipboard sharing remains disabled")
    elif args.action == "down":
        stop(manifest)
        print("Managed VM stopped normally")
    elif args.action == "baseline":
        validate_package(manifest)
        require_stopped(manifest)
        clone(vm, ROOT / "Baseline.utm")
        refresh_owned(manifest)
        print("Clean baseline saved. Use reset to restore it")
    elif args.action == "reset":
        validate_package(manifest)
        require_stopped(manifest)
        baseline = ROOT / "Baseline.utm"
        if not (baseline / "config.plist").is_file():
            raise RuntimeError("No clean baseline exists yet")
        validate_package(manifest, baseline)
        staging = ROOT / "Reset.utm"
        previous = ROOT / "Previous.utm"
        if staging.exists() or staging.is_symlink() or previous.exists() or previous.is_symlink():
            raise RuntimeError("An incomplete reset exists; preserve and inspect it before retrying")
        clone(baseline, staging)
        validate_package(manifest, staging)
        vm.rename(previous)
        try:
            staging.rename(vm)
        except BaseException:
            previous.rename(vm)
            raise
        shutil.rmtree(previous)
        print("Restored clean baseline; run up to boot")
    elif args.action == "teardown":
        owned = set(manifest.get("externalPathsCreated", []))
        before = set(manifest["externalPathsBefore"])
        candidates = sorted(owned.intersection(external_paths()) - before)
        print("Managed root:", ROOT)
        print("Recorded UTM files outside it:", json.dumps(candidates, indent=2))
        if args.preview:
            return
        for location in (Path("/Applications/UTM.app"), Path.home() / "Applications/UTM.app"):
            if location.exists():
                raise RuntimeError("Another UTM installation exists; preserve shared application data")
        registered = cli(manifest, "list")
        uuids = {value.lower() for value in re.findall(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", registered)}
        expected = {identity(manifest).lower()} if manifest.get("vmUUID") else set()
        if manifest.get("runner") == "headless" and manifest.get("vmUUID"):
            import qa_headless
            expected = qa_headless.owned_registration_ids(manifest)
        if uuids - expected:
            raise RuntimeError("Other UTM VMs are registered; preserve their application and data")
        if uuids.intersection(expected):
            require_stopped(manifest)
            cli(manifest, "delete", identity(manifest))
        terminate_owned_utm()
        busy = subprocess.run(["lsof", "-t", "+D", str(ROOT)], text=True, capture_output=True)
        if busy.stdout.strip() or busy.returncode not in (0, 1) or busy.stderr.strip():
            raise RuntimeError("Managed files are still open by a process; preserved remaining files")
        for name in candidates:
            path = Path(name)
            if path.is_symlink() or path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
        shutil.rmtree(ROOT)
        print("Removed the managed test environment and its recorded external files")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
