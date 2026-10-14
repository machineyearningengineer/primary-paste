"""Exercise destructive lifecycle guards with disposable folders and a fake UTM."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("qa_vm", Path(__file__).parents[1] / "qa_vm.py")
vm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vm)
UUID = "4E523626-4B1E-4FA8-BD20-8798E00A9B53"
OTHER = "00000000-0000-0000-0000-000000000001"


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "Managed"
        self.package = self.root / "VM/Test.utm"
        self.package.mkdir(parents=True)
        self.config = {"Information": {"UUID": UUID}, "Backend": "Apple",
                       "Virtualization": {"ClipboardSharing": False}}
        (self.package / "config.plist").write_bytes(plistlib.dumps(self.config))
        self.manifest = {"owner": "primary-paste-qa", "schema": 1, "root": str(self.root),
                         "vmPath": str(self.package), "vmUUID": UUID,
                         "externalPathsBefore": [], "externalPathsCreated": []}
        (self.root / "manifest.json").write_text(json.dumps(self.manifest))
        self.addCleanup(patch.stopall)
        patch.object(vm, "ROOT", self.root).start()
        patch.object(vm, "external_paths", return_value=[]).start()
        self.cli = patch.object(vm, "cli", return_value="stopped").start()
        self.terminate = patch.object(vm, "terminate_owned_utm").start()

    def run_action(self, *args):
        with patch("sys.argv", ["qa_vm.py", *args]), contextlib.redirect_stdout(io.StringIO()):
            vm.main()

    def test_preview_has_no_writes_or_process_actions(self):
        before = (self.root / "manifest.json").read_bytes()
        self.run_action("teardown", "--preview")
        self.assertEqual(before, (self.root / "manifest.json").read_bytes())
        self.cli.assert_not_called()
        self.terminate.assert_not_called()

    def test_unowned_manifest_is_rejected(self):
        self.manifest["owner"] = "someone-else"
        (self.root / "manifest.json").write_text(json.dumps(self.manifest))
        with self.assertRaisesRegex(RuntimeError, "ownership"):
            vm.load()

    def test_symlink_vm_parent_is_rejected(self):
        outside = Path(self.temp.name) / "Outside"
        outside.mkdir()
        self.package.rename(outside / "Test.utm")
        (self.root / "VM").rmdir()
        (self.root / "VM").symlink_to(outside)
        with self.assertRaisesRegex(RuntimeError, "outside"):
            vm.package(self.manifest)

    def test_identity_and_clipboard_guards(self):
        for config in ({**self.config, "Information": {"UUID": OTHER}},
                       {**self.config, "Virtualization": {"ClipboardSharing": True}}):
            (self.package / "config.plist").write_bytes(plistlib.dumps(config))
            with self.assertRaises(RuntimeError):
                self.run_action("up")
        self.cli.assert_not_called()

    def test_other_registered_vm_blocks_teardown(self):
        self.cli.return_value = UUID.lower() + " stopped QA\n" + OTHER + " stopped Other"
        with self.assertRaisesRegex(RuntimeError, "Other UTM VMs"):
            self.run_action("teardown")
        self.terminate.assert_not_called()
        self.assertTrue(self.package.is_dir())

    def test_busy_files_are_preserved_and_cleanup_can_retry(self):
        self.cli.return_value = "UUID Status Name"  # already unregistered
        busy = subprocess.CompletedProcess([], 0, "123\n", "")
        with patch.object(vm.subprocess, "run", return_value=busy):
            with self.assertRaisesRegex(RuntimeError, "still open"):
                self.run_action("teardown")
        self.assertTrue(self.package.is_dir())
        self.assertEqual([call.args[1] for call in self.cli.call_args_list], ["list"])
        idle = subprocess.CompletedProcess([], 1, "", "")
        with patch.object(vm.subprocess, "run", return_value=idle):
            self.run_action("teardown")
        self.assertFalse(self.root.exists())

    def test_running_guest_blocks_reset(self):
        self.cli.return_value = "started"
        with self.assertRaisesRegex(RuntimeError, "must be stopped"):
            self.run_action("reset")
        self.assertTrue(self.package.is_dir())

    def test_reset_copy_failure_keeps_existing_vm(self):
        baseline = self.root / "Baseline.utm"
        baseline.mkdir()
        (baseline / "config.plist").write_bytes(plistlib.dumps(self.config))
        with patch.object(vm, "clone", side_effect=RuntimeError("copy failed")):
            with self.assertRaisesRegex(RuntimeError, "copy failed"):
                self.run_action("reset")
        self.assertTrue((self.package / "config.plist").is_file())
        self.assertFalse((self.root / "Previous.utm").exists())

    def test_invalid_baseline_cannot_replace_working_vm(self):
        baseline = self.root / "Baseline.utm"
        baseline.mkdir()
        for config in ({**self.config, "Information": {"UUID": OTHER}},
                       {**self.config, "Virtualization": {"ClipboardSharing": True}}):
            (baseline / "config.plist").write_bytes(plistlib.dumps(config))
            with self.assertRaises(RuntimeError):
                self.run_action("reset")
            self.assertEqual(plistlib.loads((self.package / "config.plist").read_bytes()), self.config)
        (baseline / "config.plist").unlink()
        baseline.rmdir()
        baseline.symlink_to(self.package, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "outside"):
            self.run_action("reset")
        self.assertTrue(self.package.is_dir())

    def test_dangling_reset_path_is_preserved(self):
        baseline = self.root / "Baseline.utm"
        baseline.mkdir()
        (baseline / "config.plist").write_bytes(plistlib.dumps(self.config))
        staging = self.root / "Reset.utm"
        staging.symlink_to(self.root / "missing")
        with self.assertRaisesRegex(RuntimeError, "incomplete reset"):
            self.run_action("reset")
        self.assertTrue(staging.is_symlink())
        self.assertTrue(self.package.is_dir())

    def test_up_is_idempotent(self):
        self.cli.return_value = "started"
        self.run_action("up")
        self.assertEqual([call.args[1] for call in self.cli.call_args_list], ["status"])

    def test_guest_shutdown_avoids_power_button_confirmation(self):
        self.manifest["guest"] = {"host": "192.168.64.2", "user": "qa"}
        (self.root / "Keys").mkdir()
        (self.root / "Keys/guest_ed25519").touch()
        self.cli.side_effect = ["started", "stopping", "stopped"]
        with patch.object(vm.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
            vm.stop(self.manifest)
        self.assertEqual([call.args[1] for call in self.cli.call_args_list], ["status"] * 3)
        self.assertIn("--shell", run.call_args.args[0])
        self.assertIn("sudo -n /sbin/shutdown -h now", run.call_args.args[0][-1])

    def test_failed_guest_shutdown_falls_back_without_force(self):
        self.manifest["guest"] = {"host": "192.168.64.2", "user": "qa"}
        (self.root / "Keys").mkdir()
        (self.root / "Keys/guest_ed25519").touch()
        self.cli.side_effect = ["started", "started", "", "stopped"]
        with patch.object(vm.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)):
            vm.stop(self.manifest)
        self.assertEqual(self.cli.call_args_list[2].args, (self.manifest, "stop", UUID, "--request"))


if __name__ == "__main__":
    unittest.main()
