#!/usr/bin/env python3
"""Optional guest screen/input session over pinned SSH. Passwords stay in memory."""
import getpass
import hashlib
import ipaddress
import json
from pathlib import Path
import re
import secrets
import select
import struct
import subprocess
import sys
import termios
import time

from qa_vm import ROOT, load, validate_package


def screen_dependencies():
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from PIL import Image
    except ImportError as error:
        raise RuntimeError(
            "Guest screen access needs Pillow and cryptography. Use the Codex bundled Python "
            "or a dedicated QA Python environment with both installed."
        ) from error
    return Cipher, algorithms, modes, Image


class GuestScreen:
    def __init__(self, password):
        Cipher, algorithms, modes, Image = screen_dependencies()

        self.image_module = Image
        manifest = load()
        validate_package(manifest)
        guest = manifest.get("guest", {})
        user, host = guest.get("user", ""), guest.get("host", "")
        if not re.fullmatch(r"[a-z_][a-z0-9_-]*", user) or not ipaddress.ip_address(host).is_private:
            raise RuntimeError("Missing verified guest connection")
        subprocess.run([sys.executable, str(Path(__file__).with_name("qa_guest.py")), "--shell", "true"], check=True)
        keys = ROOT / "Keys"
        self.transport = subprocess.Popen([
            "ssh", "-T", "-i", str(keys / "guest_ed25519"), "-o", "IdentitiesOnly=yes",
            "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=yes",
            "-o", 'UserKnownHostsFile="' + str(keys / "known_hosts") + '"',
            "-W", "127.0.0.1:5900", user + "@" + host,
        ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
        self.pressed_keys = set()
        self.last_pointer = None
        try:
            if not self.read(12).startswith(b"RFB 003."):
                raise RuntimeError("Unexpected guest screen protocol")
            self.send(b"RFB 003.008\n")
            methods = self.read(self.read(1)[0])
            if 30 not in methods:
                raise RuntimeError("Guest must support existing-account Apple authentication")
            self.send(bytes([30]))
            generator, length = struct.unpack(">HH", self.read(4))
            if not 128 <= length <= 1024:
                raise RuntimeError("Unexpected authentication key length")
            modulus = int.from_bytes(self.read(length), "big")
            public = int.from_bytes(self.read(length), "big")
            if not 1 < generator < modulus or not 1 < public < modulus:
                raise RuntimeError("Invalid authentication parameters")
            private = secrets.randbelow(modulus - 3) + 2
            shared = pow(public, private, modulus).to_bytes(length, "big")
            key = hashlib.md5(shared, usedforsecurity=False).digest()
            credentials = bytearray(secrets.token_bytes(128))
            for offset, value in ((0, user), (64, password)):
                data = value.encode("utf-8")
                if len(data) > 63 or b"\0" in data:
                    raise RuntimeError("Unsupported credential length")
                credentials[offset:offset + len(data)] = data
                credentials[offset + len(data)] = 0
            encryptor = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
            self.send(encryptor.update(bytes(credentials)) + encryptor.finalize()
                      + pow(generator, private, modulus).to_bytes(length, "big"))
            if struct.unpack(">I", self.read(4))[0] != 0:
                raise RuntimeError("Guest authentication failed")
            self.send(b"\x01")  # Share the guest's existing session.
            header = self.read(24)
            self.width, self.height = struct.unpack(">HH", header[:4])
            name_length = struct.unpack(">I", header[20:])[0]
            if name_length > 4096:
                raise RuntimeError("Unexpected guest session name")
            self.read(name_length)
            self.check_size(self.width, self.height)
            self.canvas = Image.new("RGB", (self.width, self.height))
            pixel_format = struct.pack(">BBBBHHHBBB3x", 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
            self.send(b"\x00\0\0\0" + pixel_format)
            self.send(struct.pack(">BBHiii", 2, 0, 3, 0, -223, -224))
        except BaseException:
            self.close()
            raise

    @staticmethod
    def check_size(width, height):
        if not 0 < width <= 4096 or not 0 < height <= 4096:
            raise RuntimeError("Unexpected guest display dimensions")

    def read(self, count):
        data = bytearray()
        deadline = time.monotonic() + 20
        while len(data) < count:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.transport.stdout], [], [], remaining)[0]:
                raise RuntimeError("Guest screen response timed out; reconnect the session")
            part = self.transport.stdout.read(count - len(data))
            if not part:
                raise RuntimeError("Guest screen connection closed")
            data.extend(part)
        return bytes(data)

    def send(self, data):
        self.transport.stdin.write(data)
        self.transport.stdin.flush()

    def screenshot(self, name):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,80}\.png", name):
            raise RuntimeError("Use a simple PNG filename")
        # Apple can queue updates before the next explicit request. Discard that
        # backlog before asking for a fresh frame, after native input has settled.
        time.sleep(0.3)
        for _ in range(20):
            if not select.select([self.transport.stdout], [], [], 0.05)[0]:
                break
            self.update()
        self.send(struct.pack(">BBHHHH", 3, 0, 0, 0, self.width, self.height))
        while True:
            if self.update():
                folder = ROOT / "Screens"
                if folder.is_symlink():
                    raise RuntimeError("Guest screenshots folder must not be a symbolic link")
                folder.mkdir(exist_ok=True)
                path = folder / name
                if path.is_symlink():
                    raise RuntimeError("Guest screenshot must not replace a symbolic link")
                self.canvas.save(path)
                return str(path)
            self.send(struct.pack(">BBHHHH", 3, 0, 0, 0, self.width, self.height))

    def update(self):
        while True:
            kind = self.read(1)[0]
            if kind == 2:  # Bell
                return False
            if kind == 3:  # Clipboard text is discarded, never imported or logged.
                size = struct.unpack(">I", self.read(7)[3:])[0]
                if size > 16_777_216:
                    raise RuntimeError("Unexpected clipboard message length")
                self.read(size)
                return False
            if kind != 0:
                raise RuntimeError("Unsupported guest screen message")
            count = struct.unpack(">H", self.read(3)[1:])[0]
            updated = False
            for _ in range(count):
                x, y, w, h, encoding = struct.unpack(">HHHHi", self.read(12))
                if encoding == -224:
                    break
                if encoding == -223:
                    self.check_size(w, h)
                    self.width, self.height = w, h
                    self.canvas = self.image_module.new("RGB", (w, h))
                    continue
                if encoding != 0 or x + w > self.width or y + h > self.height:
                    raise RuntimeError("Unsupported guest screen rectangle")
                data = self.read(w * h * 4)
                self.canvas.paste(self.image_module.frombytes("RGB", (w, h), data, "raw", "BGRX"), (x, y))
                updated = True
            return updated

    def pointer(self, x, y, mask=0):
        if not 0 <= x < self.width or not 0 <= y < self.height or not 0 <= mask <= 7:
            raise RuntimeError("Input must stay within the guest display")
        self.send(struct.pack(">BBHH", 5, mask, x, y))
        self.last_pointer = (x, y)
        time.sleep(0.15)

    def key(self, code, down):
        if not 0 <= code <= 0xFFFFFFFF:
            raise RuntimeError("Invalid guest key")
        self.send(struct.pack(">BBHI", 4, int(down), 0, code))
        if down:
            self.pressed_keys.add(code)
        else:
            self.pressed_keys.discard(code)
        time.sleep(0.1)

    def close(self):
        try:
            for code in self.pressed_keys.copy():
                self.key(code, False)
            if self.last_pointer is not None:
                self.pointer(*self.last_pointer, mask=0)
        except (OSError, RuntimeError):
            pass  # The guest may have shut down; still reap our SSH transport.
        if self.transport.stdin:
            self.transport.stdin.close()
        if self.transport.stdout:
            self.transport.stdout.close()
        try:
            self.transport.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.transport.terminate()
            self.transport.wait(timeout=3)


def main():
    screen_dependencies()
    # No credentials in arguments, environment, files, or command output.
    password = getpass.getpass("Existing disposable guest password: ")
    screen = GuestScreen(password)
    del password
    original = termios.tcgetattr(sys.stdin.fileno()) if sys.stdin.isatty() else None
    if original:
        settings = termios.tcgetattr(sys.stdin.fileno())
        settings[3] &= ~termios.ECHO
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, settings)
    try:
        print(json.dumps({"ready": True, "width": screen.width, "height": screen.height}), flush=True)
        for line in sys.stdin:
            action = json.loads(line)
            if action["action"] == "quit":
                break
            if action["action"] == "screenshot":
                result = screen.screenshot(action["name"])
            elif action["action"] == "pointer":
                screen.pointer(action["x"], action["y"], action.get("mask", 0))
                result = "sent"
            elif action["action"] == "key":
                screen.key(action["code"], action["down"])
                result = "sent"
            else:
                raise RuntimeError("Unsupported guest action")
            response = {"result": result}
            if action["action"] == "screenshot":
                response.update(width=screen.width, height=screen.height)
            print(json.dumps(response), flush=True)
    finally:
        if original:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, original)
        screen.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("Guest screen session closed")
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
