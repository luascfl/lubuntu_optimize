#!/bin/sh
# Install the chrome-cdp wrapper and make it the system default browser command.
# Needs sudo only for update-alternatives. Revert with:
#   sudo update-alternatives --set x-www-browser /usr/bin/google-chrome-stable
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)/chrome-cdp"
DEST="/usr/local/bin/chrome-cdp"

sudo install -m 0755 "$SRC" "$DEST"
for name in x-www-browser gnome-www-browser; do
  sudo update-alternatives --install "/usr/bin/$name" "$name" "$DEST" 300
  sudo update-alternatives --set "$name" "$DEST"
done
update-alternatives --query x-www-browser | grep -E '^Value'
