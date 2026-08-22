# Documentation index

Use these files as the project source of truth for planning and execution.

## Canonical entrypoints
- `AGENTS.md`
- `GEMINI.md`
- `README.md`
- `.context/workflow/status.yaml`

## Core project docs
- [Project overview](./project-overview.md)
- [Architecture notes](./architecture.md)
- [Data flow](./data-flow.md)
- [Development workflow](./development-workflow.md)
- [Testing strategy](./testing-strategy.md)
- [Security notes](./security.md)
- [Tooling guide](./tooling.md)
- [Glossary](./glossary.md)

## Planning and delivery docs
- [GSD project plan](./planning_gsd/PROJECT.md)
- [GSD current state](./planning_gsd/STATE.md)
- [Ralph PRD README](../prd_ralph/README.md)
- [Ralph PRD JSON](../prd_ralph/prd.json)

## Current repository snapshot
- `README.md` is the operational narrative for ZRAM alignment and monitoring.
- `scripts/zram-monitor.sh` is the canonical runtime script path named by the README and local agent instructions.
- `scripts/install-zram-monitor.sh` installs the canonical monitor script into `/usr/local/bin/`.
- `scripts/set-swappiness.sh` and `scripts/set-swappiness-persistent.sh` manage runtime and persistent swappiness values for safe trials under the `tuning` sudo profile.
- `scripts/set-page-cluster.sh` and `scripts/set-page-cluster-persistent.sh` do the same for `vm.page-cluster`.
- `scripts/set-zswap-enabled.sh` toggles zswap in runtime, and the benchmark wrappers plus generic benchmark runner support swappiness, page-cluster, and zswap experiments under the same workload and snapshot workflow.
- `systemd/cpugov-performance.service` and the single governance script `scripts/apply-cpugov-performance-service.sh` install, enable, and verify the host CPU governor service at `/etc/systemd/system/cpugov-performance.service`.
- `zram-monitor.sh` is a duplicate copy of the same script at the repository root.
- `toggle-passwordless-sudo.sh` toggles a sudoers rule for passwordless host tuning commands or full root access, depending on profile.
- `optimize.sh` owns persistent kernel and zswap tuning; `early-oom/memory-guard.sh` owns ZRAM provisioning, EarlyOOM policy, and freeze evidence without writing `sysctl` values.
- `create_and_push_repo.sh` is a large repository publishing helper that is not referenced by the runtime monitoring flow.
- `mcp_status.txt` is an environment note, not a runtime dependency.

## Bootstrap result
- Local `AGENTS.md` and `GEMINI.md` now exist and point future execution back to the canonical planning surface.
- `.context/docs/planning_gsd/` now tracks milestone state and the next story.
- `.context/prd_ralph/prd.json` is the active Ralph source of truth.
- `.context/workflow/status.yaml` is initialized and currently points to execution phase.
