#!/bin/sh
# Thin, non-mutating-by-default launcher for the portable provisioner.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PYTHON=${PHONE_TO_OMP_PYTHON_COMMAND:-python3}
exec "$PYTHON" "$HERE/provision.py" "$@"
