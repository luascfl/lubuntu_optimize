#!/bin/sh
set -euo pipefail

LOG_FILE=${LOG_FILE:-/var/log/zram-monitor.log}
INCIDENT_LOG=${INCIDENT_LOG:-/var/log/zram-monitor-incidents.log}
PRESSURE_FILE=${PRESSURE_FILE:-/proc/pressure/memory}

MEM_INFO=$(free -m | awk 'NR==2 {print $7}')
SWAP_USED=$(free -m | awk 'NR==3 {print $3}')
ALERTS=""

if [ "$MEM_INFO" -lt 500 ]; then
  ALERTS="$ALERTS low-memory-available (${MEM_INFO}MiB)"
fi

if [ "$SWAP_USED" -gt 1024 ]; then
  ALERTS="$ALERTS high-swap-usage (${SWAP_USED}MiB)"
fi

TIMESTAMP=$(date --iso=seconds)

{
  printf -- '--- %s\n' "$TIMESTAMP"
  printf '[free -m]\n'
  free -m
  printf '\n[zramctl]\n'
  zramctl
  printf '\n[swapon --show]\n'
  swapon --show
  printf '\n[/proc/pressure/memory]\n'
  if [ -r "$PRESSURE_FILE" ]; then
    cat "$PRESSURE_FILE"
  else
    printf 'unavailable\n'
  fi
  printf '\n[alerts]\n'
  if [ -n "$ALERTS" ]; then
    printf '%s\n' "$ALERTS"
  else
    printf 'none\n'
  fi
  printf '\n'
} >> "$LOG_FILE"

if [ -n "$ALERTS" ]; then
  printf -- '--- %s ALERT%s\n' "$TIMESTAMP" "$ALERTS" >> "$INCIDENT_LOG"
fi
