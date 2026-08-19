#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

usage() {
  cat <<'EOF'
usage: run-kernel-memory-benchmark.sh <apply-script> <value> <label> <output-dir> [workload-mib] [warmup-sec] [hold-sec]

Applies one validated runtime kernel-memory helper, runs a bounded memory-pressure
workload, triggers one zram-monitor sample during the workload, and captures a snapshot.
EOF
}

apply_script=${1:-}
value=${2:-}
label=${3:-}
output_dir=${4:-}
workload_mib=${5:-768}
warmup_sec=${6:-10}
hold_sec=${7:-45}

if [ -z "$apply_script" ] || [ -z "$value" ] || [ -z "$label" ] || [ -z "$output_dir" ]; then
  usage >&2
  exit 2
fi

case "$workload_mib" in
  ''|*[!0-9]*) usage >&2; exit 2 ;;
esac
case "$warmup_sec" in
  ''|*[!0-9]*) usage >&2; exit 2 ;;
esac
case "$hold_sec" in
  ''|*[!0-9]*) usage >&2; exit 2 ;;
esac
case "$label" in
  *[!A-Za-z0-9._-]*|'')
    printf 'error: label must use only letters, digits, dot, underscore, or dash\n' >&2
    exit 2
    ;;
esac

if [ "$workload_mib" -le 0 ] || [ "$warmup_sec" -le 0 ] || [ "$hold_sec" -le 0 ]; then
  printf 'error: workload-mib, warmup-sec, and hold-sec must be positive integers\n' >&2
  exit 2
fi

case "$apply_script" in
  */*)
    resolved_apply_script=$apply_script
    ;;
  *)
    resolved_apply_script="$SCRIPT_DIR/$apply_script"
    ;;
esac

if [ ! -x "$resolved_apply_script" ]; then
  printf 'error: apply script is not executable: %s\n' "$resolved_apply_script" >&2
  exit 1
fi

mkdir -p "$output_dir"
snapshot_path="$output_dir/$label.snapshot.txt"
meta_path="$output_dir/$label.meta.txt"
workload_log="$output_dir/$label.workload.log"

printf 'apply_script=%s\n' "$resolved_apply_script"
printf 'applying_value=%s\n' "$value"
sudo -n "$resolved_apply_script" "$value"

printf 'label=%s\n' "$label" > "$meta_path"
printf 'apply_script=%s\n' "$resolved_apply_script" >> "$meta_path"
printf 'applied_value=%s\n' "$value" >> "$meta_path"
printf 'workload_mib=%s\n' "$workload_mib" >> "$meta_path"
printf 'warmup_sec=%s\n' "$warmup_sec" >> "$meta_path"
printf 'hold_sec=%s\n' "$hold_sec" >> "$meta_path"

"$SCRIPT_DIR/run-memory-pressure-workload.sh" "$workload_mib" "$hold_sec" > "$workload_log" 2>&1 &
workload_pid=$!

sleep "$warmup_sec"
sudo -n systemctl start zram-monitor.service
"$SCRIPT_DIR/capture-swappiness-snapshot.sh" "$label" "$snapshot_path" >/dev/null

workload_status=0
if ! wait "$workload_pid"; then
  workload_status=$?
fi
printf 'workload_status=%s\n' "$workload_status" >> "$meta_path"

printf 'snapshot=%s\n' "$snapshot_path"
printf 'meta=%s\n' "$meta_path"
printf 'workload_log=%s\n' "$workload_log"

exit "$workload_status"
