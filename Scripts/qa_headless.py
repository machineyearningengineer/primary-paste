"""Owned headless runner for the existing Apple-virtualization UTM package."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import time

from qa_vm import ROOT, identity, package, terminate_owned_utm, validate_package


def safe_path(name):
    path = ROOT / name
    if path.resolve() != path:
        raise RuntimeError("Runner paths must not be symbolic links")
    return path


def process(manifest):
    state_file = safe_path("runner-state.json")
    if not state_file.exists():
        return None
    record = json.loads(state_file.read_text())
    if record.get("owner") != "primary-paste-qa" or record.get("uuid") != identity(manifest):
        raise RuntimeError("Headless runner identity does not match the owned guest")
    pid = record.get("pid")
    if not isinstance(pid, int) or pid <= 1:
        raise RuntimeError("Invalid runner process record")
    if record.get("state") not in {"starting", "started", "stopped", "failed"}:
        raise RuntimeError("Invalid runner state; preserve the guest for inspection")
    result = subprocess.run(["ps", "-p", str(pid), "-o", "comm="], text=True, capture_output=True, timeout=5)
    if not result.stdout.strip():
        return None
    if result.stdout.strip() != str(safe_path("Tools/qa-vm-runner")):
        raise RuntimeError("Runner PID belongs to a different executable; no signal was sent")
    return record


def require_idle_storage(manifest):
    data = package(manifest) / "Data"
    if data.is_symlink() or not data.is_dir():
        raise RuntimeError("Missing or unsafe guest storage directory")
    result = subprocess.run(["lsof", "-t", "+D", str(data)], text=True, capture_output=True, timeout=15)
    if result.stdout.strip() or result.stderr.strip() or result.returncode not in (0, 1):
        raise RuntimeError("Guest storage is open; preserve it until its owner shuts down normally")


def status(manifest):
    record = process(manifest)
    if record:
        return "stopping" if record["state"] == "stopped" else record["state"]
    require_idle_storage(manifest)
    return "stopped"


def start(manifest):
    validate_package(manifest)
    record = process(manifest)
    if record:
        if record["state"] != "started":
            raise RuntimeError("Guest startup is pending or failed; inspect runner.log before retrying")
        return
    require_idle_storage(manifest)
    if set(registered(manifest).lower().split()) - owned_registration_ids(manifest):
        raise RuntimeError("Other UTM registrations exist; preserve their running application")
    terminate_owned_utm()
    source = Path(__file__).with_name("qa_vm_runner.swift")
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    executable = safe_path("Tools/qa-vm-runner")
    stamp = safe_path("Tools/runner-source.sha256")
    entitlements = safe_path("Tools/runner.entitlements")
    if not executable.is_file() or not stamp.is_file() or stamp.read_text().strip() != digest:
        entitlements.write_bytes(plistlib.dumps({"com.apple.security.virtualization": True}))
        subprocess.run(["xcrun", "swiftc", "-O", "-target", "arm64-apple-macosx14.0", str(source),
                        "-o", str(executable)], check=True, timeout=60)
        subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements", str(entitlements),
                        str(executable)], check=True, timeout=15)
        stamp.write_text(digest + "\n")
    subprocess.run(["codesign", "--verify", "--strict", str(executable)], check=True, timeout=15)
    log = safe_path("runner.log")
    with log.open("w") as output:
        child = subprocess.Popen([str(executable)], stdin=subprocess.DEVNULL, stdout=output,
                                 stderr=subprocess.STDOUT, start_new_session=True, cwd=ROOT)
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        if child.poll() is not None:
            raise RuntimeError("Guest runner exited before startup; see the owned runner.log")
        record = process(manifest)
        if record and record["pid"] == child.pid and record["state"] == "started":
            return
        time.sleep(0.2)
    raise RuntimeError("Guest startup is still pending; inspect runner.log before retrying")


def request_stop(manifest):
    record = process(manifest)
    if record:
        os.kill(record["pid"], signal.SIGTERM)


def registration_data():
    # No Apple Events or host Automation grant. Preserve all unrelated UTM data.
    prefs = Path.home() / "Library/Containers/com.utmapp.UTM/Data/Library/Preferences/com.utmapp.UTM.plist"
    if not prefs.exists():
        return {"VMEntryList": [], "Registry": {}}
    if prefs.is_symlink():
        raise RuntimeError("UTM registration file must not be a symbolic link")
    return plistlib.loads(prefs.read_bytes())


def registered(manifest):
    data = registration_data()
    entries = data.get("VMEntryList")
    if not isinstance(entries, list) or any(not isinstance(x, str) or
            not re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", x) for x in entries):
        raise RuntimeError("Unrecognized UTM registry; preserve its files")
    return "\n".join(entries)


def owned_registration_ids(manifest):
    # UTM assigns a registration UUID on import. A relocated original can leave
    # an obsolete canonical entry plus an alias for this same package. Recognize
    # only aliases resolving to the exact validated owned package; never edit the
    # registry or infer ownership from the display name.
    owned = {identity(manifest).lower()}
    data = registration_data()
    registry = data.get("Registry", {})
    if not isinstance(registry, dict):
        raise RuntimeError("Unrecognized UTM registry; preserve its files")
    for key, value in registry.items():
        if not re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", key) or \
                not isinstance(value, dict) or value.get("UUID") != key:
            raise RuntimeError("Unrecognized UTM registration identity")
        location = value.get("Package", {})
        if not isinstance(location, dict):
            raise RuntimeError("Unrecognized UTM package registration")
        path = location.get("Path")
        if isinstance(path, str) and Path(path).resolve() == package(manifest).resolve():
            owned.add(key.lower())
    return owned


def unregister_owned(manifest):
    require_idle_storage(manifest)
    container = str(Path.home() / "Library/Containers/com.utmapp.UTM")
    if container not in manifest.get("externalPathsCreated", []) or container in manifest["externalPathsBefore"]:
        raise RuntimeError("UTM registration data predates this guest; preserve it")
    owned = owned_registration_ids(manifest)
    entries = set(registered(manifest).lower().split())
    registry = {key.lower() for key in registration_data().get("Registry", {})}
    if not entries or entries - owned or registry - owned:
        raise RuntimeError("Other or unknown UTM registrations exist; preserve them")
    terminate_owned_utm()
    # The exclusively owned container is removed by teardown after its busy-file
    # check. No live UTM database is edited and no foreign VM is unregistered.
