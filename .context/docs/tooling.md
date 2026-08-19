# Tooling guide

## Runtime commands used by the monitor
- `free -m`
- `zramctl`
- `swapon --show`
- `date --iso=seconds`

## Host level commands documented in the README
- `swapoff /dev/zram0`
- `modprobe -r zram`
- `modprobe zram algo=lz4`
- `systemctl restart zramswap`
- Inspection of `/etc/default/earlyoom`

## Privilege helper shipped in the repository
- `toggle-passwordless-sudo.sh` enables, disables, or inspects a sudoers rule for the current user.
- Default profile `tuning` limits passwordless sudo to `systemctl` calls for `zram-monitor`, `zramswap`, `earlyoom`, the install helper `scripts/install-zram-monitor.sh`, the swappiness helpers `scripts/set-swappiness.sh` and `scripts/set-swappiness-persistent.sh`, the page-cluster helpers `scripts/set-page-cluster.sh` and `scripts/set-page-cluster-persistent.sh`, and the zswap helper `scripts/set-zswap-enabled.sh`.
- Optional profile `full` writes `NOPASSWD: ALL` for the selected user and is intentionally higher risk.

## Install and tuning helpers shipped in the repository
- `scripts/install-zram-monitor.sh` installs `scripts/zram-monitor.sh` into `/usr/local/bin/zram-monitor.sh`.
- `scripts/set-swappiness.sh` applies a runtime `vm.swappiness` value through `/usr/sbin/sysctl` after validating that it is between `0` and `200`.
- `scripts/set-swappiness-persistent.sh` writes a managed file in `/etc/sysctl.d/` and applies the same `vm.swappiness` value immediately, also validating the `0..200` range.
- `scripts/set-page-cluster.sh` applies a runtime `vm.page-cluster` value after validating that it is between `0` and `8`.
- `scripts/set-page-cluster-persistent.sh` writes a managed file in `/etc/sysctl.d/` and applies the same `vm.page-cluster` value immediately.
- `scripts/set-zswap-enabled.sh` toggles `/sys/module/zswap/parameters/enabled` between `0` and `1`.
- `scripts/capture-swappiness-snapshot.sh` captures a structured before or after snapshot for a VM tuning experiment, including swappiness, page-cluster, vfs cache pressure, zram, zswap, and PSI fields.
- `scripts/compare-swappiness-snapshots.sh` compares two snapshots and prints a simple assessment.
- `scripts/run-memory-pressure-workload.sh` generates a bounded pressure workload for reproducible swappiness, page-cluster, or zswap trials.
- `scripts/run-kernel-memory-benchmark.sh` orchestrates one benchmark by setting a helper value, running the workload, triggering the monitor, and capturing a stressed snapshot.
- `scripts/run-swappiness-benchmark.sh`, `scripts/run-page-cluster-benchmark.sh`, and `scripts/run-zswap-benchmark.sh` are thin wrappers around the generic benchmark runner.
- `scripts/zram-monitor.sh` also accepts `LOG_FILE` and `INCIDENT_LOG` environment overrides for non-root validation.

## Expected host integrations
- `systemd` for periodic execution
- `logrotate` for log retention
- Write access to `/usr/local/bin` and `/var/log` during installation
- Write access to `/etc/sudoers.d` when enabling passwordless sudo on the host

## Authoring and validation tools
- `dash -n` for shell syntax checks
- `python3 -m json.tool` for PRD validation
- `read`, `search`, and `ai-coders-context` for repository inspection and planning state updates

## Repository utilities not on the runtime path
- `create_and_push_repo.sh` is a publishing helper for repositories.
- `mcp_status.txt` is an environment snapshot and not part of deployment.

## Missing tooling to add in future cycles
- A validation script that checks ZRAM config alignment and monitor prerequisites.
- Versioned `systemd` and `logrotate` files so the README stops being the only source for deployment details.

## Related resources
- [Project overview](./project-overview.md)
- [Architecture notes](./architecture.md)
- [Testing strategy](./testing-strategy.md)
