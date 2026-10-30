#!/usr/bin/env python3
"""Capture real shell integration output without displaying escape sequences."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent / "src/shell-integration"
OSC = re.compile(rb"\x1b\](\d+);([^\x07\x1b]*)\x07")


class ShellNotificationTests(unittest.TestCase):
    def test_bash_expanded_directory_title(self):
        with tempfile.TemporaryDirectory(prefix="zashiki-shell-security-") as tmp:
            directory = Path(tmp) / "日本語\\a\x1b\x07\r\n\x7f"
            directory.mkdir()
            env = dict(os.environ, ZASHIKI_SHELL_FEATURES="title", SECURITY_TEST_DIR=str(directory), PS1="")
            env.pop("ZASHIKI_BASH_INJECT", None)
            commands = f'source "{ROOT / "bash/ghostty.bash"}"\ncd -- "$SECURITY_TEST_DIR"\nexit\n'
            result = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-i"],
                input=commands.encode(), env=env, capture_output=True, check=True,
            )
            titles = [value for kind, value in OSC.findall(result.stdout + result.stderr) if kind == b"2"]
            self.assertTrue(titles)
            self.assertTrue(any("日本語".encode() in value for value in titles))
            for value in titles:
                self.assertIsNone(re.search(rb"[\x00-\x1f\x7f]", value))

    def capture(self, shell, directory, command):
        env = dict(os.environ, ZASHIKI_SHELL_FEATURES="title")
        env.pop("ZASHIKI_BASH_INJECT", None)
        if shell == "zsh":
            # Noninteractive sourcing skips the tty-opening entrypoint. Explicitly
            # initialize with fd 1 so every byte goes to the captured pipe.
            script = '''
source "$1"
typeset -gi _ghostty_fd=1 _ghostty_state=0
HOST=$'host\\e\\a'
cd -- "$2"
_ghostty_deferred_init
_ghostty_precmd
_ghostty_preexec "$3"
'''
            args = ["/bin/zsh", "-f", "-c", script, "test", str(ROOT / "zsh/ghostty-integration")]
        else:
            script = '''
source "$1"
HOSTNAME=$'host\\e\\a'
cd -- "$2"
__ghostty_precmd
__ghostty_preexec "$3"
'''
            args = ["/bin/bash", "--noprofile", "--norc", "-ic", script, "test", str(ROOT / "bash/ghostty.bash")]
        result = subprocess.run(args + [str(directory), command], env=env, capture_output=True, check=True)
        return result.stdout

    def test_cwd_and_titles(self):
        for shell in ("zsh", "bash"):
            for name in ("日本語 space", r"literal\a\e]52;c;payload\a", "raw\x1b\x07\r\n\t\x7f", "unicode\u0085\u009b"):
                with self.subTest(shell=shell, name=repr(name)), tempfile.TemporaryDirectory(prefix="zashiki-shell-security-") as tmp:
                    directory = Path(tmp) / name
                    directory.mkdir()
                    command = "echo 日本語 \\a\x1b\x07\r\n\x7f"
                    data = self.capture(shell, directory, command)
                    records = OSC.findall(data)
                    # Check the stream framing as well as payloads. An injected
                    # ESC/BEL would leave unmatched bytes or a new OSC record.
                    self.assertNotIn(b"\x1b", OSC.sub(b"", data))
                    self.assertNotIn(b"\x07", OSC.sub(b"", data))
                    self.assertTrue(records)
                    self.assertTrue(all(kind in (b"2", b"7", b"133") for kind, _ in records))
                    cwd = [value for kind, value in records if kind == b"7"]
                    self.assertTrue(cwd)
                    clean_name = re.sub(r"[\x00-\x1f\x7f-\x9f]", "", name).encode()
                    self.assertTrue(all(value.endswith(clean_name) for value in cwd))
                    for kind, value in records:
                        if kind in (b"2", b"7"):
                            self.assertIsNone(re.search(rb"[\x00-\x1f\x7f]", value))
                            self.assertIsNone(re.search(r"[\x80-\x9f]", value.decode()))
                    titles = [value for kind, value in records if kind == b"2"]
                    self.assertTrue(titles)
                    self.assertIn("日本語".encode(), titles[-1])
                    self.assertIn(b"\\a", titles[-1])


if __name__ == "__main__":
    unittest.main()
