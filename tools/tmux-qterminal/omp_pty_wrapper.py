#!/usr/bin/env python3
"""Run an interactive command under a real PTY with pass-through I/O.

Version 3 features:
- optional log file mirroring (--log)
- timeout (--timeout)
- built-in presets (--preset bash|python|top|vim)
- JSON diagnostics mode (--json)

Notes:
- In normal mode, child output is streamed to stdout.
- In --json mode, child output is streamed to stderr so stdout can stay pure JSON.
- The child always receives TERM=xterm-256color and a real PTY.
"""

from __future__ import annotations

import argparse
import errno
import fcntl
import json
import os
import pty
import select
import signal
import struct
import sys
import termios
import time
import tty
from pathlib import Path

DEFAULT_ROWS = 40
DEFAULT_COLS = 120
BRACKETED_PASTE_START = b"\x1b[200~"
BRACKETED_PASTE_END = b"\x1b[201~"
BACKSPACE = b"\x08"
DELETE = b"\x7f"
DELETE_KEY_SEQUENCE = b"\x1b[3~"


def normalize_parent_input(data: bytes) -> bytes:
    # QTerminal pode envolver paste com bracketed-paste e codificar Backspace
    # como ^H. O child usa uma PTY canônica cujo erase padrão é ^?.
    cleaned = data.replace(BRACKETED_PASTE_START, b"").replace(BRACKETED_PASTE_END, b"")
    return cleaned.replace(DELETE_KEY_SEQUENCE, DELETE).replace(BACKSPACE, DELETE)
PRESETS = {
    "bash": [os.environ.get("SHELL", "/bin/bash")],
    "python": [sh for sh in [shutil.which("python3") if 'shutil' in globals() else None] if sh] or [sys.executable],
    "top": ["top"],
    "vim": ["vim"],
}

# Avoid a top-level shutil import just for one preset.
import shutil  # noqa: E402
PRESETS["python"] = [shutil.which("python3") or sys.executable]


def get_size(fd: int) -> tuple[int, int]:
    try:
        data = fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8)
        rows, cols, _, _ = struct.unpack("HHHH", data)
        if rows > 0 and cols > 0:
            return rows, cols
    except OSError:
        pass
    return DEFAULT_ROWS, DEFAULT_COLS


def set_size(fd: int, rows: int, cols: int) -> None:
    data = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, data)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a command under an interactive PTY wrapper for Oh-My-Pi testing.")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Command after -- to run inside the PTY.")
    parser.add_argument("--preset", choices=sorted(PRESETS), help="Use a built-in preset command when no explicit command is passed.")
    parser.add_argument("--timeout", type=float, default=0.0, help="Kill the child after N seconds. 0 disables timeout.")
    parser.add_argument("--log", help="Optional path to mirror the raw PTY output.")
    parser.add_argument("--json", action="store_true", help="Emit a JSON diagnostic summary on stdout. Child output goes to stderr.")
    return parser.parse_args()


def resolve_argv(args: argparse.Namespace) -> list[str]:
    argv = args.command
    if argv and argv[0] == "--":
        argv = argv[1:]
    if argv:
        return argv
    if args.preset:
        return PRESETS[args.preset]
    return PRESETS["bash"]


def terminate_child(pid: int) -> None:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.kill(pid, sig)
        except OSError:
            return
        time.sleep(0.2)


def main() -> int:
    args = parse_args()
    argv = resolve_argv(args)

    pid, master_fd = pty.fork()

    if pid == 0:
        env = os.environ.copy()
        env["TERM"] = "xterm-256color"
        os.execvpe(argv[0], argv, env)

    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stderr.fileno() if args.json else sys.stdout.fileno()
    old_attrs = None
    log_file = None
    bytes_from_child = 0
    bytes_from_parent = 0
    timed_out = False
    start_ts = time.time()
    rows, cols = get_size(stdin_fd if os.isatty(stdin_fd) else stdout_fd)

    if args.log:
        log_path = Path(args.log).expanduser().resolve()
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_file = log_path.open("ab")
    else:
        log_path = None

    def resize(_signum=None, _frame=None) -> None:
        current_rows, current_cols = get_size(stdin_fd if os.isatty(stdin_fd) else stdout_fd)
        try:
            set_size(master_fd, current_rows, current_cols)
        except OSError:
            pass
        try:
            os.kill(pid, signal.SIGWINCH)
        except OSError:
            pass

    signal.signal(signal.SIGWINCH, resize)
    resize()

    try:
        if os.isatty(stdin_fd):
            old_attrs = termios.tcgetattr(stdin_fd)
            tty.setraw(stdin_fd)

        watched = [master_fd]
        if os.isatty(stdin_fd):
            watched.append(stdin_fd)

        while True:
            timeout = None
            if args.timeout and args.timeout > 0:
                remaining = start_ts + args.timeout - time.time()
                if remaining <= 0:
                    timed_out = True
                    terminate_child(pid)
                    break
                timeout = remaining

            readable, _, _ = select.select(watched, [], [], timeout)
            if not readable:
                timed_out = True
                terminate_child(pid)
                break

            if stdin_fd in readable:
                data = os.read(stdin_fd, 4096)
                if not data:
                    break
                data = normalize_parent_input(data)
                bytes_from_parent += len(data)
                if data:
                    os.write(master_fd, data)

            if master_fd in readable:
                try:
                    data = os.read(master_fd, 4096)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                bytes_from_child += len(data)
                os.write(stdout_fd, data)
                if log_file is not None:
                    log_file.write(data)
                    log_file.flush()
    finally:
        if old_attrs is not None:
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_attrs)
        if log_file is not None:
            log_file.close()
        try:
            os.close(master_fd)
        except OSError:
            pass

    _, status = os.waitpid(pid, 0)
    child_status = os.waitstatus_to_exitcode(status)
    exit_code = 128 - child_status if child_status < 0 else child_status

    if args.json:
        payload = {
            "argv": argv,
            "exit_code": exit_code,
            "timed_out": timed_out,
            "parent_stdin_isatty": os.isatty(stdin_fd),
            "term_for_child": "xterm-256color",
            "tty_size": {"rows": rows, "cols": cols},
            "bytes_from_parent": bytes_from_parent,
            "bytes_from_child": bytes_from_child,
            "log_path": str(log_path) if log_path else None,
        }
        print(json.dumps(payload, ensure_ascii=False))

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
