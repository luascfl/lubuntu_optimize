#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage: run-memory-pressure-workload.sh [mib] [hold-sec]

Allocates and touches a bounded amount of memory, then keeps it resident for
hold-sec seconds. Intended for comparative swappiness trials.
EOF
}

mib=${1:-768}
hold_sec=${2:-45}

case "$mib" in
  ''|*[!0-9]*)
    usage >&2
    exit 2
    ;;
esac
case "$hold_sec" in
  ''|*[!0-9]*)
    usage >&2
    exit 2
    ;;
esac

if [ "$mib" -le 0 ] || [ "$hold_sec" -le 0 ]; then
  printf 'error: mib and hold-sec must be positive integers\n' >&2
  exit 2
fi

python3 - "$mib" "$hold_sec" <<'PY'
import sys
import time

mib = int(sys.argv[1])
hold_sec = int(sys.argv[2])
chunk_bytes = 64 * 1024 * 1024
page = 4096
remaining = mib * 1024 * 1024
blocks: list[bytearray] = []
allocated = 0

print(f'memory_workload_target_mib={mib}', flush=True)
print(f'memory_workload_hold_sec={hold_sec}', flush=True)

while remaining > 0:
    size = min(chunk_bytes, remaining)
    block = bytearray(size)
    for offset in range(0, size, page):
        block[offset] = 1
    blocks.append(block)
    allocated += size
    remaining -= size
    print(f'allocated_mib={allocated // (1024 * 1024)}', flush=True)
    time.sleep(0.2)

end = time.monotonic() + hold_sec
while time.monotonic() < end:
    checksum = 0
    for block in blocks:
        checksum ^= block[0]
    print(f'heartbeat_checksum={checksum}', flush=True)
    time.sleep(1)

print('memory_workload_status=completed', flush=True)
PY
