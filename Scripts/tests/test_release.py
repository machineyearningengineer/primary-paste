import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ("PrimaryPaste.xcodeproj", "PrimaryPaste", "Packaging/npm"):
            (self.root / directory).mkdir(parents=True)
        (self.root / "VERSION").write_text("0.1.0\n")
        (self.root / "BUILD_NUMBER").write_text("1\n")
        (self.root / "LICENSE").write_text("GNU GENERAL PUBLIC LICENSE\n")
        (self.root / "PrimaryPaste.xcodeproj/project.pbxproj").write_text(
            "MARKETING_VERSION = 0.1.0;\nCURRENT_PROJECT_VERSION = 1;\n" * 2)
        (self.root / "PrimaryPaste/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleShortVersionString": "$(MARKETING_VERSION)",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
            "LicensingEnabled": False,
            "LicensingEnforcementEnabled": False,
        }))
        self.package = self.root / "Packaging/npm/package.json"
        self.package.write_text(json.dumps({"version": "0.1.0", "license": "GPL-3.0-only", "private": True}))

    def test_version_mirrors_and_monotonic_build(self):
        release.set_version("0.2.0", 2, self.root)
        release.check(self.root, links=False)
        self.assertEqual(release.state(self.root), ("0.2.0", 2))
        self.assertEqual(json.loads(self.package.read_text())["version"], "0.2.0")
        with self.assertRaisesRegex(ValueError, "not decrease"):
            release.set_version("0.3.0", 1, self.root)
        with self.assertRaisesRegex(ValueError, "new build number"):
            release.set_version("0.3.0", 2, self.root)
        with self.assertRaisesRegex(ValueError, "not decrease"):
            release.set_version("0.1.0", 3, self.root)

    def test_invalid_versions_rejected_without_changes(self):
        for version in ("v0.1.0", "01.0.0", "1.2", "1.2.3-beta", "1.2.3;evil", "999999.0.0"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                release.set_version(version, 2, self.root)
        self.assertEqual(release.state(self.root), ("0.1.0", 1))

    def test_preview_rebuilds_have_distinct_names_and_exact_source(self):
        first = release.release_label("0.1.0", 2, True)
        rebuilt = release.release_label("0.1.0", 3, True)
        self.assertNotEqual(first, rebuilt)
        self.assertIn("build-3", rebuilt)
        self.assertIn("UNSIGNED-PREVIEW", rebuilt)
        self.assertEqual(release.release_label("0.1.0", 3, False), "Primary-Paste-0.1.0-macOS-universal")
        commit = "a" * 40
        text = release.source_information("0.1.0", 3, commit, False)
        self.assertIn(f"/tree/{commit}", text)
        self.assertNotIn("/tree/v0.1.0", text)
        with self.assertRaisesRegex(ValueError, "exact Git commit"):
            release.source_information("0.1.0", 3, "main", False)

    def test_missing_build_configuration_does_not_partially_write(self):
        project = self.root / "PrimaryPaste.xcodeproj/project.pbxproj"
        project.write_text("MARKETING_VERSION = 0.1.0;\nCURRENT_PROJECT_VERSION = 1;\n")
        with self.assertRaisesRegex(ValueError, "no version files changed"):
            release.set_version("0.2.0", 2, self.root)
        self.assertEqual(release.state(self.root), ("0.1.0", 1))

    def test_drift_and_implicit_install_hooks_rejected(self):
        for mutation in ({"version": "0.2.0"}, {"license": "MIT"}, {"private": False}, {"scripts": {"postinstall": "launch"}}):
            package = {"version": "0.1.0", "license": "GPL-3.0-only", "private": True, **mutation}
            self.package.write_text(json.dumps(package))
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                release.check(self.root, links=False)

    def test_cask_rejects_fake_checksum_and_pins_immutable_release(self):
        with self.assertRaises(ValueError):
            release.cask("0.1.0", "TODO")
        text = release.cask("0.1.0", "a" * 64)
        self.assertIn("/releases/download/v#{version}/", text)
        self.assertNotIn("latest", text)
        self.assertNotIn("--no-quarantine", text)
        self.assertIn('depends_on macos: ">= :sonoma"', text)

    def test_protected_release_configuration_not_enabled_by_mistake(self):
        info = self.root / "PrimaryPaste/Info.plist"
        data = plistlib.loads(info.read_bytes())
        data["LicensingEnforcementEnabled"] = True
        info.write_bytes(plistlib.dumps(data))
        with self.assertRaisesRegex(ValueError, "unverified licensing"):
            release.check(self.root, links=False)

    def test_both_app_and_helper_must_be_universal(self):
        app = self.root / "Primary Paste.app"
        (app / "Contents").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.abel.primarypaste",
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
        }))
        for values in (("arm64", "arm64 x86_64"), ("arm64 x86_64", "x86_64"),
                       ("arm64 i386", "arm64 x86_64")):
            with self.subTest(values=values), patch.object(release, "run", side_effect=values):
                with self.assertRaisesRegex(ValueError, "universal binary"):
                    release.verify_app(app, "0.1.0", 1)
        with patch.object(release, "run", side_effect=("x86_64 arm64", "arm64 x86_64")):
            release.verify_app(app, "0.1.0", 1)


if __name__ == "__main__":
    unittest.main()
