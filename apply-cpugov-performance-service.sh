#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SRC_UNIT=${SRC_UNIT:-"$REPO_ROOT/systemd/cpugov-performance.service"}
DEST_UNIT=${DEST_UNIT:-/etc/systemd/system/cpugov-performance.service}
SYSTEMCTL_BIN=${SYSTEMCTL_BIN:-/usr/bin/systemctl}
CPUFREQ_GLOB=${CPUFREQ_GLOB:-/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor}
UNIT_NAME=$(basename "$DEST_UNIT")
status=0

report_error() {
  printf 'error: %s\n' "$1" >&2
  status=1
}

if [ "$(id -u)" -ne 0 ]; then
  printf 'error: run with sudo so install, enable, and verification use the same privilege boundary\n' >&2
  printf 'usage: sudo -n %s\n' "$0" >&2
  exit 1
fi

if [ ! -f "$SRC_UNIT" ]; then
  printf 'error: source unit not found: %s\n' "$SRC_UNIT" >&2
  exit 1
fi

if [ ! -x "$SYSTEMCTL_BIN" ]; then
  printf 'error: systemctl not found or not executable: %s\n' "$SYSTEMCTL_BIN" >&2
  exit 1
fi

install -m 0644 "$SRC_UNIT" "$DEST_UNIT"
"$SYSTEMCTL_BIN" daemon-reload
"$SYSTEMCTL_BIN" enable --now "$UNIT_NAME"
printf 'installed and enabled %s -> %s\n' "$SRC_UNIT" "$DEST_UNIT"

if ! cmp -s "$SRC_UNIT" "$DEST_UNIT"; then
  report_error "installed unit differs from source: $DEST_UNIT"
else
  printf 'unit file: ok (%s)\n' "$DEST_UNIT"
fi

if "$SYSTEMCTL_BIN" is-enabled "$UNIT_NAME" >/dev/null 2>&1; then
  printf 'enabled: yes (%s)\n' "$UNIT_NAME"
else
  report_error "unit is not enabled: $UNIT_NAME"
fi

result=$("$SYSTEMCTL_BIN" show "$UNIT_NAME" --property=Result --value 2>/dev/null || true)
case "$result" in
  ''|success)
    printf 'last result: %s\n' "${result:-unknown}"
    ;;
  *)
    report_error "last unit result is $result"
    ;;
esac

found=0
for governor in $CPUFREQ_GLOB; do
  [ -e "$governor" ] || continue
  found=1
  value=$(cat "$governor")
  printf '%s=%s\n' "$governor" "$value"
  if [ "$value" != "performance" ]; then
    report_error "governor is not performance: $governor=$value"
  fi
done

if [ "$found" -eq 0 ]; then
  report_error "no CPU governor files found under $CPUFREQ_GLOB"
fi

exit "$status"
