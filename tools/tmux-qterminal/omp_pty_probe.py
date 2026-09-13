#!/usr/bin/env python3
"""Allocate a real PTY for a child command and print what the child sees.

Why this exists:
- Oh-My-Pi can run shell commands with or without a parent TTY.
- Some tools only care that *their own child process* sees a PTY.
- This script creates that PTY explicitly, so you can test behavior in a
  reproducible way.

Usage:
  python3 tools/tmux-qterminal/omp_pty_probe.py
      Runs the built-in probe and prints JSON from inside the child PTY.

  python3 tools/tmux-qterminal/omp_pty_probe.py -- bash -lc 'python3 -c "import os; print(os.isatty(0))"'
      Runs an arbitrary command under a PTY.

Exit code:
- mirrors the child command exit code.
"""

from __future__ import annotations

import argparse
import json
import os
import pty
import shutil
import struct
import sys
import termios
import fcntl


DEFAULT_ROWS = 40
DEFAULT_COLS = 120


def current_tty_size() -> tuple[int, int]:
    for fd in (sys.stdin, sys.stdout, sys.stderr):
        try:
            fileno = fd.fileno()
        except Exception:
            continue
        if not os.isatty(fileno):
            continue
        try:
            packed = fcntl.ioctl(fileno, termios.TIOCGWINSZ, b"\0" * 8)
            rows, cols, _, _ = struct.unpack("HHHH", packed)
            if rows > 0 and cols > 0:
                return rows, cols
        except OSError:
            continue
    return DEFAULT_ROWS, DEFAULT_COLS


def set_pty_size(fd: int, rows: int, cols: int) -> None:
    packed = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, packed)


def default_probe_command() -> list[str]:
    py = shutil.which("python3") or sys.executable
    code = r'''
import json, os, shutil, sys, termios, fcntl, struct

def tty_size(fd):
    try:
        packed = fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8)
        rows, cols, _, _ = struct.unpack("HHHH", packed)
        return {"rows": rows, "cols": cols}
    except OSError as e:
        return {"error": str(e)}

payload = {
    "stdin_isatty": os.isatty(0),
    "stdout_isatty": os.isatty(1),
    "stderr_isatty": os.isatty(2),
    "tty_name": os.ttyname(0) if os.isatty(0) else None,
    "term": os.getenv("TERM"),
    "shell": os.getenv("SHELL"),
    "cwd": os.getcwd(),
    "tty_size": tty_size(0),
}
print(json.dumps(payload, ensure_ascii=False))
'''
    return [py, "-c", code]


def run_under_pty(argv: list[str]) -> int:
    pid, master_fd = pty.fork()

    if pid == 0:
        env = os.environ.copy()
        env["TERM"] = "xterm-256color"
        os.execvpe(argv[0], argv, env)

    rows, cols = current_tty_size()
    set_pty_size(master_fd, rows, cols)

    chunks: list[bytes] = []
    try:
        while True:
            try:
                data = os.read(master_fd, 4096)
            except OSError:
                break
            if not data:
                break
            chunks.append(data)
    finally:
        try:
            os.close(master_fd)
        except OSError:
            pass

    _, status = os.waitpid(pid, 0)
    sys.stdout.buffer.write(b"".join(chunks))
    sys.stdout.flush()
    return os.waitstatus_to_exitcode(status)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a command under an explicit PTY for Oh-My-Pi compatibility testing.")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Command after -- to run inside the PTY.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    argv = args.command
    if argv and argv[0] == "--":
        argv = argv[1:]
    if not argv:
        argv = default_probe_command()
    return run_under_pty(argv)


if __name__ == "__main__":
    raise SystemExit(main())
