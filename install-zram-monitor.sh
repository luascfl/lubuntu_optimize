#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC_SCRIPT=${SRC_SCRIPT:-"$SCRIPT_DIR/zram-monitor.sh"}
DEST_SCRIPT=${DEST_SCRIPT:-/usr/local/bin/zram-monitor.sh}

if [ ! -f "$SRC_SCRIPT" ]; then
  printf 'error: source script not found: %s\n' "$SRC_SCRIPT" >&2
  exit 1
fi

install -m 0755 "$SRC_SCRIPT" "$DEST_SCRIPT"
printf 'installed %s -> %s\n' "$SRC_SCRIPT" "$DEST_SCRIPT"
