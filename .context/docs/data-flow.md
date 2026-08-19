# Data flow

## Runtime inputs
| Source | Purpose | Current location |
| --- | --- | --- |
| `/etc/default/zramswap` | Desired compression algorithm reference | Described in `README.md` |
| `free -m` | Available memory and swap used values | Called by monitor script |
| `zramctl` | Active ZRAM device, algorithm, and compression state | Called by monitor script |
| `swapon --show` | Active swap device information | Called by monitor script |
| `/proc/pressure/memory` | Kernel memory pressure signal | Called by monitor script |
| `date --iso=seconds` | Timestamp for append only records | Called by monitor script |

## Processing pipeline
1. Read current memory figures from `free -m`.
2. Extract available memory from row 2, column 7.
3. Extract swap used from row 3, column 3.
4. Compare those values against two fixed thresholds, 500 MiB available memory and 1024 MiB swap used.
5. Build an alert string when either threshold is crossed.
6. Append a structured log block with timestamp, `free -m`, `zramctl`, `swapon --show`, `/proc/pressure/memory`, and alert status.
7. If alerts exist, append a single line summary to the incident log.

## Outputs and sinks
| Output | Sink | Purpose |
| --- | --- | --- |
| Snapshot block | `/var/log/zram-monitor.log` | Historical operational record |
| Incident summary line | `/var/log/zram-monitor-incidents.log` | Quick scan for bad episodes |
| Manual operator checks | Terminal commands from `README.md` | Human verification after config changes |

## State model
There is no in memory service state or persistent application database. Host logs are the only durable output produced by the monitor. The desired ZRAM algorithm is managed outside the repository, via the host configuration described in the README.

## External integrations
- **Kernel module management**: `modprobe -r zram` and `modprobe zram algo=lz4` are part of the documented remediation flow.
- **systemd scheduler**: Intended to trigger the monitor every 10 minutes, but repository owned unit files do not exist yet.
- **logrotate**: Intended to retain monitor history, but repository owned config does not exist yet.
- **earlyoom**: Mentioned as a neighboring safeguard in the README, but not managed by the script.

## Failure modes
- Missing or permission denied writes to `/var/log` prevent durable monitoring output.
- Unexpected `free -m` formatting would break the column extraction logic.
- Missing `zramctl`, `swapon`, or `/proc/pressure/memory` would reduce observability.
- A mismatch between README instructions and unversioned host assets can leave the repo state and host state out of sync.

## Related resources
- [Architecture notes](./architecture.md)
- [Testing strategy](./testing-strategy.md)
- [GSD project plan](./planning_gsd/PROJECT.md)
