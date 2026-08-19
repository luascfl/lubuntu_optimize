# Glossary

## ZRAM
Compressed block device in RAM used here as swap backing for a low memory system.

## zramswap
Host side configuration and service layer that defines desired ZRAM behavior, including the `ALGO` value referenced by the README.

## Compression algorithm
The algorithm used by the `zram` kernel module, such as `lz4`. The README expects the active kernel setting to match the configured `ALGO` value.

## Available memory
The value extracted from `free -m`, row 2 column 7, used by the monitor as a low memory signal.

## Swap used
The value extracted from `free -m`, row 3 column 3, used by the monitor as a high pressure signal.

## Incident log
`/var/log/zram-monitor-incidents.log`, the compact file that receives one line summaries only when a threshold is crossed.

## Snapshot log
`/var/log/zram-monitor.log`, the append only file that stores full observation blocks for each monitor run.

## systemd timer
The scheduled trigger that the README says should run the monitor every 10 minutes. The timer is described, but its versioned unit file is not in the repository yet.

## logrotate
The host mechanism that should retain and compress monitor logs. The README references it, but its repository managed config is not present yet.

## Ralph story
A single unit of executable work defined in `.context/prd_ralph/prd.json`. Only one story should be active in a cycle.

## GSD milestone
The macro planning checkpoint tracked in `.context/docs/planning_gsd/PROJECT.md` and `.context/docs/planning_gsd/STATE.md`.
