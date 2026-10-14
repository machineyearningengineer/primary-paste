"""Protect existing VM storage and foreign host processes during headless QA."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import qa_headless as runner
import qa_vm

UUID = "4E523626-4B1E-4FA8-BD20-8798E00A9B53"


class HeadlessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.package = self.root / "VM/Test.utm"
        (self.package / "Data").mkdir(parents=True)
        self.manifest = {"owner": "primary-paste-qa", "schema": 1, "vmUUID": UUID,
                         "vmPath": str(self.package), "externalPathsBefore": [], "externalPathsCreated": []}
        self.addCleanup(patch.stopall)
        patch.object(runner, "ROOT", self.root).start()
        patch.object(runner, "package", return_value=self.package).start()
        self.state = self.root / "runner-state.json"
        self.state.write_text(json.dumps({"owner": "primary-paste-qa", "uuid": UUID, "pid": 123,
                                          "state": "started"}))

    def test_reused_pid_cannot_receive_a_shutdown_signal(self):
        with patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "/other/app\n")), \
                patch.object(runner.os, "kill") as kill:
            with self.assertRaisesRegex(RuntimeError, "different executable"):
                runner.request_stop(self.manifest)
            kill.assert_not_called()

    def test_foreign_guest_identity_is_rejected(self):
        self.state.write_text(json.dumps({"owner": "someone-else", "uuid": UUID, "pid": 123}))
        with patch.object(runner.subprocess, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "identity"):
                runner.process(self.manifest)
            run.assert_not_called()

    def test_invalid_state_never_signals_a_process(self):
        self.state.write_text(json.dumps({"owner": "primary-paste-qa", "uuid": UUID, "pid": 123,
                                          "state": "unknown"}))
        with patch.object(runner.os, "kill") as kill:
            with self.assertRaisesRegex(RuntimeError, "Invalid runner state"):
                runner.request_stop(self.manifest)
            kill.assert_not_called()

    def test_wrong_guest_and_forced_stop_cannot_reach_utm(self):
        self.manifest["runner"] = "headless"
        with patch.object(qa_vm.subprocess, "run") as run:
            for command, arguments in [("start", ("foreign",)), ("stop", (UUID, "--kill")),
                                       ("delete", ("foreign",)), ("unsupported", ())]:
                with self.assertRaises(RuntimeError):
                    qa_vm.cli(self.manifest, command, *arguments)
            run.assert_not_called()

    def test_symlinked_state_does_not_escape_owned_root(self):
        self.state.unlink()
        self.state.symlink_to(self.root / "missing")
        with self.assertRaisesRegex(RuntimeError, "symbolic"):
            runner.process(self.manifest)

    def test_absent_runner_does_not_imply_idle_storage(self):
        self.state.unlink()
        with patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "222\n", "")):
            with self.assertRaisesRegex(RuntimeError, "storage is open"):
                runner.status(self.manifest)

    def test_dead_runner_and_idle_storage_report_stopped(self):
        with patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "")):
            self.assertEqual(runner.status(self.manifest), "stopped")

    def test_started_runner_does_not_rebuild_or_launch_another_process(self):
        with patch.object(runner, "process", return_value={"pid": 123, "state": "started"}), \
                patch.object(runner, "validate_package"), patch.object(runner, "require_idle_storage") as idle, \
                patch.object(runner.subprocess, "Popen") as launch:
            runner.start(self.manifest)
            idle.assert_not_called()
            launch.assert_not_called()

    def test_teardown_preserves_preexisting_registration_data(self):
        with patch.object(runner, "require_idle_storage"), patch.object(runner, "terminate_owned_utm") as terminate:
            with self.assertRaisesRegex(RuntimeError, "predates"):
                runner.unregister_owned(self.manifest)
            terminate.assert_not_called()

    def test_start_preserves_utm_when_another_guest_is_registered(self):
        with patch.object(runner, "process", return_value=None), patch.object(runner, "validate_package"), \
                patch.object(runner, "require_idle_storage"), patch.object(runner, "registered", return_value="foreign"), \
                patch.object(runner, "terminate_owned_utm") as terminate:
            with self.assertRaisesRegex(RuntimeError, "Other UTM registrations"):
                runner.start(self.manifest)
            terminate.assert_not_called()

    def test_import_alias_is_owned_only_when_it_resolves_to_this_package(self):
        alias = "21C55C4A-98EE-4F7A-A2AF-B6188E54695B"
        foreign = "AAAA1111-BBBB-2222-CCCC-333333333333"
        data = {"Registry": {alias: {"UUID": alias, "Package": {"Path": str(self.package)}},
                             foreign: {"UUID": foreign, "Package": {"Path": str(self.root / "Other.utm")}}}}
        with patch.object(runner, "registration_data", return_value=data):
            self.assertEqual(runner.owned_registration_ids(self.manifest), {UUID.lower(), alias.lower()})

    def test_utm_event_error_cannot_masquerade_as_an_empty_registry(self):
        (self.root / "Tools/UTM.app/Contents/MacOS").mkdir(parents=True)
        (self.root / "Tools/UTM.app/Contents/MacOS/utmctl").touch()
        with patch.object(qa_vm, "ROOT", self.root), patch.object(qa_vm.subprocess, "run",
                return_value=subprocess.CompletedProcess([], 0, "UUID Status Name\n",
                                                         "Error from event: OSStatus -10004")):
            with self.assertRaisesRegex(RuntimeError, "Error from event"):
                qa_vm.cli(self.manifest, "list")


if __name__ == "__main__":
    unittest.main()
