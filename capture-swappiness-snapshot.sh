#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage: capture-swappiness-snapshot.sh <label> [output-file]

Captures the current swappiness-related host state into a snapshot file.
If output-file is omitted, the snapshot is written to stdout.
EOF
}

label=${1:-}
output_path=${2:-}

if [ -z "$label" ]; then
  usage >&2
  exit 2
fi

case "$label" in
  *[!A-Za-z0-9._-]*|'')
    printf 'error: label must use only letters, digits, dot, underscore, or dash\n' >&2
    exit 2
    ;;
esac

timestamp=$(date --iso=seconds)
swappiness=$(sysctl vm.swappiness | awk '{print $3}')
page_cluster=$(sysctl vm.page-cluster | awk '{print $3}')
vfs_cache_pressure=$(sysctl vm.vfs_cache_pressure | awk '{print $3}')
mem_available_mib=$(free -m | awk 'NR==2 {print $7}')
swap_used_mib=$(free -m | awk 'NR==3 {print $3}')
swapfile_used_bytes=$(swapon --show=NAME,USED --noheadings --bytes | awk '$1=="/swapfile" {print $2}')
zram_swap_used_bytes=$(swapon --show=NAME,USED --noheadings --bytes | awk '$1=="/dev/zram0" {print $2}')
zram_data_bytes=$(zramctl --noheadings --bytes --output NAME,DATA | awk '$1=="/dev/zram0" {print $2}')
zram_comp_bytes=$(zramctl --noheadings --bytes --output NAME,COMPR | awk '$1=="/dev/zram0" {print $2}')
zswap_enabled=$(if [ -f /sys/module/zswap/parameters/enabled ]; then cat /sys/module/zswap/parameters/enabled; else printf 'unavailable'; fi)
zswap_compressor=$(if [ -f /sys/module/zswap/parameters/compressor ]; then cat /sys/module/zswap/parameters/compressor; else printf 'unavailable'; fi)
zswap_max_pool_percent=$(if [ -f /sys/module/zswap/parameters/max_pool_percent ]; then cat /sys/module/zswap/parameters/max_pool_percent; else printf 'unavailable'; fi)
pressure_some_avg10=$(awk '/^some / {for (i=1; i<=NF; i++) if ($i ~ /^avg10=/) {split($i, a, "="); print a[2]}}' /proc/pressure/memory)
pressure_some_avg60=$(awk '/^some / {for (i=1; i<=NF; i++) if ($i ~ /^avg60=/) {split($i, a, "="); print a[2]}}' /proc/pressure/memory)
pressure_some_avg300=$(awk '/^some / {for (i=1; i<=NF; i++) if ($i ~ /^avg300=/) {split($i, a, "="); print a[2]}}' /proc/pressure/memory)
pressure_full_avg10=$(awk '/^full / {for (i=1; i<=NF; i++) if ($i ~ /^avg10=/) {split($i, a, "="); print a[2]}}' /proc/pressure/memory)
pressure_full_avg60=$(awk '/^full / {for (i=1; i<=NF; i++) if ($i ~ /^avg60=/) {split($i, a, "="); print a[2]}}' /proc/pressure/memory)
pressure_full_avg300=$(awk '/^full / {for (i=1; i<=NF; i++) if ($i ~ /^avg300=/) {split($i, a, "="); print a[2]}}' /proc/pressure/memory)

emit_snapshot() {
  printf 'label=%s\n' "$label"
  printf 'timestamp=%s\n' "$timestamp"
  printf 'swappiness=%s\n' "$swappiness"
  printf 'page_cluster=%s\n' "$page_cluster"
  printf 'vfs_cache_pressure=%s\n' "$vfs_cache_pressure"
  printf 'mem_available_mib=%s\n' "$mem_available_mib"
  printf 'swap_used_mib=%s\n' "$swap_used_mib"
  printf 'swapfile_used_bytes=%s\n' "${swapfile_used_bytes:-0}"
  printf 'zram_swap_used_bytes=%s\n' "${zram_swap_used_bytes:-0}"
  printf 'zram_data_bytes=%s\n' "${zram_data_bytes:-0}"
  printf 'zram_comp_bytes=%s\n' "${zram_comp_bytes:-0}"
  printf 'zswap_enabled=%s\n' "$zswap_enabled"
  printf 'zswap_compressor=%s\n' "$zswap_compressor"
  printf 'zswap_max_pool_percent=%s\n' "$zswap_max_pool_percent"
  printf 'pressure_some_avg10=%s\n' "$pressure_some_avg10"
  printf 'pressure_some_avg60=%s\n' "$pressure_some_avg60"
  printf 'pressure_some_avg300=%s\n' "$pressure_some_avg300"
  printf 'pressure_full_avg10=%s\n' "$pressure_full_avg10"
  printf 'pressure_full_avg60=%s\n' "$pressure_full_avg60"
  printf 'pressure_full_avg300=%s\n' "$pressure_full_avg300"
  printf '\n'
  printf '[free -m]\n'
  free -m
  printf '\n[swapon --show]\n'
  swapon --show
  printf '\n[zramctl]\n'
  zramctl
  printf '\n[zswap]\n'
  printf 'enabled=%s\n' "$zswap_enabled"
  printf 'compressor=%s\n' "$zswap_compressor"
  printf 'max_pool_percent=%s\n' "$zswap_max_pool_percent"
  printf '\n[/proc/pressure/memory]\n'
  cat /proc/pressure/memory
}

if [ -n "$output_path" ]; then
  emit_snapshot > "$output_path"
  printf 'snapshot written to %s\n' "$output_path"
else
  emit_snapshot
fi
