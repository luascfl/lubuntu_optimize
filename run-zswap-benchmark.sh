#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
exec "$SCRIPT_DIR/run-kernel-memory-benchmark.sh" "$SCRIPT_DIR/set-zswap-enabled.sh" "$@"
