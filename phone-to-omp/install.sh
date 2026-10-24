#!/bin/sh
# Install the phone-to-omp listener as a systemd user service. Safe to re-run:
# the token is created once and kept, files and unit are overwritten in place.
# Uninstall: systemctl --user disable --now phone-to-omp; rm ~/.config/systemd/user/phone-to-omp.service
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin/phone-to-omp"
CFG="$HOME/.config/phone-to-omp"
UNIT_DIR="$HOME/.config/systemd/user"

mkdir -p "$HOME/.local/bin" "$CFG" "$UNIT_DIR"
chmod 700 "$CFG"
install -m 0755 "$HERE/phone_to_omp.py" "$BIN"

if [ ! -s "$CFG/token" ]; then
  umask 077
  python3 -c 'import secrets; print(secrets.token_urlsafe(32))' > "$CFG/token"
fi
chmod 600 "$CFG/token"

cat > "$UNIT_DIR/phone-to-omp.service" <<EOF
[Unit]
Description=Type phone dictation into omp over Tailscale
After=network-online.target

[Service]
ExecStart=$BIN
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable phone-to-omp >/dev/null 2>&1
systemctl --user restart phone-to-omp

echo "Service: $(systemctl --user is-active phone-to-omp)"
echo "URL:     http://$(tailscale ip -4 | head -1):8765/"
echo "Token:   $CFG/token (send as the X-Token header; never commit it)"
