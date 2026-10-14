#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/.artifacts"
WORK_DIR="$(mktemp -d "$ROOT_DIR/.artifacts/cli-smoke.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

python3 - "$ROOT_DIR" "$WORK_DIR" <<'PY'
from pathlib import Path
import sys
root, work = map(Path, sys.argv[1:])
version = (root / "VERSION").read_text().strip()
source = (root / "Scripts/primary_paste_cli.swift").read_text()
(work / "cli.swift").write_text(source.replace("__RELEASE_VERSION__", version))
PY

xcrun swiftc -O "$WORK_DIR/cli.swift" -o "$WORK_DIR/primary-paste"
python3 - "$ROOT_DIR" "$WORK_DIR/primary-paste" <<'PY'
from pathlib import Path
import subprocess
import sys
root = Path(sys.argv[1]); cli = sys.argv[2]
for arguments in ([], ["help"], ["--help"]):
    result = subprocess.run([cli, *arguments], capture_output=True, text=True, check=True)
    assert "Usage:" in result.stdout
result = subprocess.run([cli, "version"], capture_output=True, text=True, check=True)
assert result.stdout.strip() == (root / "VERSION").read_text().strip()
for arguments in (["unknown"], ["start", "--force"]):
    result = subprocess.run([cli, *arguments], capture_output=True, text=True)
    assert result.returncode == 2
print("Native CLI compile/help/version/rejection smoke passed; no app launched.")
PY
