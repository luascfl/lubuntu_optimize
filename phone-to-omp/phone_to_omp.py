#!/usr/bin/env python3
"""Receive dictated text from the phone over Tailscale and type it into an omp tmux pane.

Security model:
  * binds only to this machine's Tailscale IPv4 address (never 0.0.0.0);
  * requires the shared token in the X-Token header;
  * body is capped, control characters are stripped and newlines become spaces,
    so the text can never press Enter or inject terminal escape sequences.
The text is only typed. Review it and press Enter yourself.
"""
import hmac
import http.server
import os
import re
import subprocess
import sys
import time
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("PHONE_TO_OMP_DIR", Path.home() / ".config" / "phone-to-omp"))
TOKEN_FILE = CONFIG_DIR / "token"
PORT = int(os.environ.get("PHONE_TO_OMP_PORT", "8765"))
MAX_BYTES = 8192
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")


def tailscale_ip():
    out = subprocess.run(["tailscale", "ip", "-4"], capture_output=True, text=True, timeout=10)
    ip = out.stdout.strip().splitlines()[0] if out.returncode == 0 and out.stdout.strip() else ""
    return ip


def clean(text):
    text = text.replace("\r\n", " ").replace("\n", " ").replace("\r", " ").replace("\t", " ")
    return CONTROL.sub("", text).strip()


def pick_pane():
    """Most recently active tmux pane running omp; PHONE_TO_OMP_PANE overrides."""
    forced = os.environ.get("PHONE_TO_OMP_PANE")
    if forced:
        return forced
    out = subprocess.run(
        ["tmux", "list-panes", "-a", "-F", "#{window_activity} #{pane_id} #{pane_current_command}"],
        capture_output=True, text=True, timeout=5,
    )
    best = None
    for line in out.stdout.splitlines():
        parts = line.split(" ", 2)
        if len(parts) == 3 and parts[2].strip() == "omp":
            if best is None or int(parts[0]) > best[0]:
                best = (int(parts[0]), parts[1])
    return best[1] if best else None


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "phone-to-omp"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.client_address[0], fmt % args))

    def _reply(self, code, msg):
        body = msg.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._reply(200, "ok")

    def do_POST(self):
        token = self.server.token
        if not hmac.compare_digest(self.headers.get("X-Token", ""), token):
            return self._reply(403, "forbidden")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self._reply(400, "bad length")
        if length <= 0 or length > MAX_BYTES:
            return self._reply(413, "empty or too large")
        text = clean(self.rfile.read(length).decode("utf-8", "replace"))
        if not text:
            return self._reply(400, "empty after cleaning")
        pane = pick_pane()
        if not pane:
            return self._reply(409, "no omp pane found")
        subprocess.run(["tmux", "send-keys", "-t", pane, "-l", text + " "], check=True, timeout=5)
        self.log_message("typed %d chars into %s", len(text), pane)
        self._reply(200, "typed")


def main():
    if not TOKEN_FILE.exists():
        sys.exit("missing token file: %s (run install.sh)" % TOKEN_FILE)
    token = TOKEN_FILE.read_text().strip()
    while True:
        ip = tailscale_ip()
        if ip:
            break
        sys.stderr.write("waiting for tailscale...\n")
        time.sleep(5)
    server = http.server.ThreadingHTTPServer((ip, PORT), Handler)
    server.token = token
    sys.stderr.write("listening on %s:%d\n" % (ip, PORT))
    server.serve_forever()


if __name__ == "__main__":
    main()
