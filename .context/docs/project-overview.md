# Project overview

## Purpose
`lubuntu_optimize` is a small operational repository for keeping a low RAM Lubuntu notebook stable under memory pressure. The current focus is ZRAM alignment and lightweight monitoring for a Dell Inspiron 3583 with 4 GiB of RAM.

## Problem statement
The README documents a working manual procedure, but the repository is still closer to an operator notebook than to a reproducible maintenance kit. It explains how to align `ALGO` in `/etc/default/zramswap`, how to reload the `zram` module, and how to monitor memory and swap, yet the versioned assets for service install, timer install, and log rotation are still missing.

## Current capabilities
- Documents the intended ZRAM algorithm alignment flow.
- Provides a `zram-monitor.sh` script that appends `free -m`, `zramctl`, and `swapon --show` snapshots to `/var/log/zram-monitor.log`.
- Records incident lines in `/var/log/zram-monitor-incidents.log` when available memory drops below 500 MiB or swap use exceeds 1024 MiB.
- Captures the desired operational target in the README, including service, timer, and logrotate expectations.

## Target user
The current user is the machine owner or maintainer who can run privileged commands on a Lubuntu laptop and wants a stable, repeatable setup for memory pressure management.

## In-repo assets
| Asset | Role | Notes |
| --- | --- | --- |
| `README.md` | Operational narrative | Main source for current desired behavior |
| `scripts/zram-monitor.sh` | Runtime monitor script | Canonical script path mentioned by README |
| `zram-monitor.sh` | Duplicate script copy | Same content as `scripts/zram-monitor.sh`, creates drift risk |
| `create_and_push_repo.sh` | Repo publishing utility | Not part of ZRAM runtime path |
| `mcp_status.txt` | Environment snapshot | Informational only |

## Current gaps
- No versioned `systemd` unit or timer files, despite README references.
- No versioned `logrotate` configuration, despite README references.
- No installation helper to place scripts and units into system locations.
- No validation script or automated quality gate beyond manual operator checks.
- No local PRD, GSD state, or workflow status existed before this bootstrap.

## Success state for the next cycles
The repository should evolve from a note plus script into a reproducible system maintenance kit with versioned deployment assets, explicit validation commands, and a single canonical monitor script path.

## Related resources
- [Architecture notes](./architecture.md)
- [Data flow](./data-flow.md)
- [GSD project plan](./planning_gsd/PROJECT.md)
- [Ralph PRD README](../prd_ralph/README.md)
