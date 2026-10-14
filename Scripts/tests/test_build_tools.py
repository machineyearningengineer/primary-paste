"""Exercise macOS Bash argument handling without compiling, signing or launching."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BuildArgumentTests(unittest.TestCase):
    def test_default_and_explicit_signing_arguments_survive_macos_bash(self):
        with tempfile.TemporaryDirectory() as folder:
            temporary = Path(folder)
            tools = temporary / "bin"
            tools.mkdir()
            (tools / "swift").write_text("#!/bin/sh\nexit 0\n")
            (tools / "xcodebuild").write_text(
                "#!/usr/bin/env python3\nimport json,os,sys\n"
                "from pathlib import Path\nPath(os.environ['PRIMARY_PASTE_TEST_ARGS']).write_text(json.dumps(sys.argv[1:]))\n")
            for tool in tools.iterdir():
                tool.chmod(0o755)
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       PRIMARY_PASTE_TEST_ARGS=str(temporary / "args.json"))
            for key in ("DEVELOPMENT_TEAM", "CODE_SIGN_IDENTITY", "CODE_SIGN_STYLE"):
                env.pop(key, None)
            for overrides in ({}, {"DEVELOPMENT_TEAM": "", "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_STYLE": "Manual"}):
                with self.subTest(overrides=overrides):
                    subprocess.run(["/bin/bash", str(ROOT / "Scripts/package_app.sh")],
                                   env={**env, **overrides}, check=True, stdout=subprocess.DEVNULL)
                    args = json.loads((temporary / "args.json").read_text())
                    self.assertIn("Primary Paste", args)
                    self.assertEqual(args[-1], "build")
                    for key, value in overrides.items():
                        self.assertIn(f"{key}={value}", args)
                    self.assertNotIn("", args)
