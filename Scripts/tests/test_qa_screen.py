import io
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import qa_screen


class GuestScreenBoundaryTests(unittest.TestCase):
    def test_missing_dependencies_fail_before_credentials_or_connection(self):
        for module in ['cryptography.hazmat.primitives.ciphers', 'PIL']:
            with self.subTest(module=module), patch.dict(sys.modules, {module: None}), \
                    patch.object(qa_screen.getpass, 'getpass') as password, \
                    patch.object(qa_screen.subprocess, 'Popen') as transport:
                with self.assertRaisesRegex(RuntimeError, 'Pillow and cryptography'):
                    qa_screen.main()
                password.assert_not_called()
                transport.assert_not_called()

    def screen(self):
        screen = qa_screen.GuestScreen.__new__(qa_screen.GuestScreen)
        screen.width, screen.height = 100, 100
        screen.transport = Mock()
        screen.canvas = Mock()
        screen.pressed_keys = set()
        screen.last_pointer = None
        return screen

    def test_malformed_rectangles_rejected_before_pixel_read(self):
        for rectangle in [(90, 0, 20, 10, 0), (0, 0, 10, 10, 7), (0, 0, 0, 10, -223)]:
            with self.subTest(rectangle=rectangle):
                screen = self.screen()
                screen.read = Mock(side_effect=[b'\0', b'\0\0\1', struct.pack('>HHHHi', *rectangle)])
                with self.assertRaises(RuntimeError):
                    screen.update()
                self.assertEqual(screen.read.call_count, 3)
                screen.canvas.paste.assert_not_called()

    def test_clipboard_and_bell_do_not_wait_for_an_unrequested_frame(self):
        screen = self.screen()
        screen.read = Mock(side_effect=[b'\3', b'\0\0\0' + struct.pack('>I', 5), b'hello'])
        self.assertFalse(screen.update())
        self.assertEqual(screen.read.call_count, 3)
        screen.read = Mock(return_value=b'\2')
        self.assertFalse(screen.update())
        screen.read.assert_called_once_with(1)

    def test_stalled_or_closed_transport_fails(self):
        screen = self.screen()
        with patch.object(qa_screen.select, 'select', return_value=([], [], [])):
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                screen.read(1)
        screen.transport.stdout = io.BytesIO()
        with patch.object(qa_screen.select, 'select', return_value=([screen.transport.stdout], [], [])):
            with self.assertRaisesRegex(RuntimeError, 'closed'):
                screen.read(1)

    def test_screenshot_symlinks_do_not_escape_owned_folder(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            elsewhere = root / 'elsewhere'
            elsewhere.mkdir()
            (root / 'Screens').symlink_to(elsewhere, target_is_directory=True)
            screen = self.screen()
            screen.update = Mock(return_value=True)
            with patch.object(qa_screen, 'ROOT', root), patch.object(qa_screen.time, 'sleep'), \
                    patch.object(qa_screen.select, 'select', return_value=([], [], [])):
                with self.assertRaisesRegex(RuntimeError, 'symbolic link'):
                    screen.screenshot('sample.png')
            screen.canvas.save.assert_not_called()

    def test_close_releases_guest_input_and_reaps_ssh(self):
        screen = self.screen()
        screen.pressed_keys = {65511}
        screen.last_pointer = (12, 34)
        screen.key, screen.pointer = Mock(), Mock()
        screen.close()
        screen.key.assert_called_once_with(65511, False)
        screen.pointer.assert_called_once_with(12, 34, mask=0)
        screen.transport.stdin.close.assert_called_once()
        screen.transport.stdout.close.assert_called_once()
        screen.transport.wait.assert_called_once_with(timeout=3)


if __name__ == '__main__':
    unittest.main()
