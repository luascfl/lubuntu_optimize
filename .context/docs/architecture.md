# Architecture notes

## System architecture overview
The repository is a documentation first operations package. Its runtime surface is a shell monitor that samples kernel memory and swap state, then appends observations to host log files. The repository does not ship an application server, database, or API. Its effective architecture is a host automation loop centered on system utilities that already exist on Lubuntu.

## Architectural layers
- **Operational documentation**: `README.md` explains the intended host configuration and expected runtime behavior.
- **Runtime monitor**: `scripts/zram-monitor.sh` collects system state and emits append only logs.
- **Host integrations**: Lubuntu services and files outside the repo, chiefly `/etc/default/zramswap`, `/var/log/*`, and the future `systemd` and `logrotate` assets described in the README.
- **Repository utilities**: `create_and_push_repo.sh` supports repository publishing and is separate from the runtime monitor path.

## Detected design patterns
| Pattern | Confidence | Locations | Description |
| --- | --- | --- | --- |
| Append only operational log | High | `scripts/zram-monitor.sh`, `zram-monitor.sh` | The monitor never edits historical state, it appends snapshots and alerts to log files. |
| Threshold based incident detection | High | `scripts/zram-monitor.sh`, `zram-monitor.sh` | Incident logging is driven by fixed numeric thresholds for available memory and swap usage. |
| Documentation as control plane | High | `README.md` | The repository currently relies on README instructions to describe deployment assets that are not yet versioned. |
| Duplicate runtime entrypoint | High | `scripts/zram-monitor.sh`, `zram-monitor.sh` | The same monitor exists in two locations, which increases drift risk. |

## Entry points
- [`README.md`](../../README.md), operator entrypoint for manual setup and verification.
- [`scripts/zram-monitor.sh`](../../scripts/zram-monitor.sh), canonical runtime script named by the README.
- [`zram-monitor.sh`](../../zram-monitor.sh), duplicate repository root script.
- [`create_and_push_repo.sh`](../../create_and_push_repo.sh), repository publishing helper.

## Public API
| Symbol | Type | Location |
| --- | --- | --- |
| `scripts/zram-monitor.sh` | Executable shell script | `scripts/zram-monitor.sh` |
| `zram-monitor.sh` | Executable shell script | `zram-monitor.sh` |
| `README.md` operational procedure | Human interface | `README.md` |

## Internal system boundaries
The monitor script owns observation and logging. Host level configuration owns the actual ZRAM setup and service scheduling. The README currently bridges those two areas manually. Future cycles should replace that manual bridge with versioned service, timer, logrotate, and install assets.

## External service dependencies
- **Kernel and procfs/sysfs views**: `zramctl`, `free`, `swapon`, and the `zram` module expose the state the script records.
- **systemd**: Referenced by the README for periodic execution, but the unit files are not stored in the repository yet.
- **logrotate**: Referenced by the README for log retention, but the config file is not stored in the repository yet.

## Key decisions and trade offs
The current design stays intentionally simple. It avoids a daemon and relies on scheduled execution plus flat log files. That keeps runtime overhead low on a constrained machine, but it shifts correctness pressure onto deployment discipline because the repository does not yet version every host artifact it documents.

## Risks and constraints
- Changes that touch `/etc/default/zramswap`, module loading, or `/var/log` require elevated privileges on the host.
- The monitor uses hard coded log paths, which makes test isolation harder.
- Duplicate script copies can diverge silently.
- The repository is not currently a Git repository in this workspace, so normal commit based traceability is unavailable until that is corrected.

## Top directories snapshot
- `scripts/`, one runtime script copy.
- `.context/docs/`, project context and planning docs.
- `.context/prd_ralph/`, Ralph planning artifacts.
- `.context/workflow/`, workflow state.
- `.taskmaster/`, legacy planning directory that is outside the active workflow requested for this repository.

## Related resources
- [Project overview](./project-overview.md)
- [Data flow](./data-flow.md)
- [GSD current state](./planning_gsd/STATE.md)
