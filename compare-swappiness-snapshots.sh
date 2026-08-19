#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage: compare-swappiness-snapshots.sh <before-snapshot> <after-snapshot>

Compares two snapshot files created by capture-swappiness-snapshot.sh.
EOF
}

before_path=${1:-}
after_path=${2:-}

if [ -z "$before_path" ] || [ -z "$after_path" ]; then
  usage >&2
  exit 2
fi

python3 - "$before_path" "$after_path" <<'PY'
import sys
from decimal import Decimal
from pathlib import Path

before_path = Path(sys.argv[1])
after_path = Path(sys.argv[2])


def parse_snapshot(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    with path.open('r', encoding='utf-8') as handle:
        for line in handle:
            line = line.rstrip('\n')
            if not line:
                break
            key, value = line.split('=', 1)
            data[key] = value
    return data


def as_int(data: dict[str, str], key: str) -> int:
    return int(data[key])


def as_decimal(data: dict[str, str], key: str) -> Decimal:
    return Decimal(data[key])


def format_signed_int(value: int, unit: str) -> str:
    return f"{value:+d} {unit}"


def format_signed_decimal(value: Decimal) -> str:
    return f"{value:+.2f}"

before = parse_snapshot(before_path)
after = parse_snapshot(after_path)

metrics = [
    ('swappiness', 'swappiness', 'raw-int'),
    ('page_cluster', 'page-cluster', 'raw-int'),
    ('vfs_cache_pressure', 'vfs cache pressure', 'raw-int'),
    ('mem_available_mib', 'mem available', 'MiB'),
    ('swap_used_mib', 'swap used', 'MiB'),
    ('pressure_some_avg60', 'pressure some avg60', 'decimal'),
    ('pressure_full_avg60', 'pressure full avg60', 'decimal'),
]

print(f"before: {before.get('label', before_path.name)} @ {before.get('timestamp', 'unknown')}")
print(f"after:  {after.get('label', after_path.name)} @ {after.get('timestamp', 'unknown')}")
print()

for key, label, kind in metrics:
    if kind == 'raw-int':
        before_value = as_int(before, key)
        after_value = as_int(after, key)
        delta = after_value - before_value
        print(f"{label}: {before_value} -> {after_value} ({format_signed_int(delta, '')[:-1]})")
    elif kind == 'MiB':
        before_value = as_int(before, key)
        after_value = as_int(after, key)
        delta = after_value - before_value
        print(f"{label}: {before_value} MiB -> {after_value} MiB ({format_signed_int(delta, 'MiB')})")
    elif kind == 'decimal':
        before_value = as_decimal(before, key)
        after_value = as_decimal(after, key)
        delta = after_value - before_value
        print(f"{label}: {before_value:.2f} -> {after_value:.2f} ({format_signed_decimal(delta)})")

before_swapfile = as_int(before, 'swapfile_used_bytes')
after_swapfile = as_int(after, 'swapfile_used_bytes')
before_zram = as_int(before, 'zram_swap_used_bytes')
after_zram = as_int(after, 'zram_swap_used_bytes')
print()
print(f"swapfile used: {before_swapfile} B -> {after_swapfile} B ({after_swapfile - before_swapfile:+d} B)")
print(f"zram swap used: {before_zram} B -> {after_zram} B ({after_zram - before_zram:+d} B)")
print()
print(f"zswap enabled: {before.get('zswap_enabled', 'unknown')} -> {after.get('zswap_enabled', 'unknown')}")

mem_ok = as_int(after, 'mem_available_mib') >= 400
swap_improved = as_int(after, 'swap_used_mib') < as_int(before, 'swap_used_mib')
pressure_improved = as_decimal(after, 'pressure_some_avg60') <= as_decimal(before, 'pressure_some_avg60') and as_decimal(after, 'pressure_full_avg60') <= as_decimal(before, 'pressure_full_avg60')

page_cluster_changed = before.get('page_cluster') != after.get('page_cluster')

print()
if mem_ok and swap_improved and pressure_improved:
    print('assessment: improved swap and pressure while preserving the memory floor')
elif not mem_ok:
    print('assessment: after-snapshot fell below the 400 MiB memory floor')
elif page_cluster_changed and pressure_improved and as_int(after, 'swap_used_mib') == as_int(before, 'swap_used_mib'):
    print('assessment: better pressure with flat swap usage, evaluate interactively before keeping the new page-cluster value')
else:
    print('assessment: mixed result, inspect the raw sections before keeping the new value')
PY
