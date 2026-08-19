# Testing strategy

## Current baseline
The repository has no automated test harness yet. Validation is currently command driven and host oriented.

## Baseline quality gates
These commands should remain green after planning or script changes:
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Manual verification path from the README
After changes that affect host behavior, validate with:
- `zramctl`
- `free -h`
- `swapon --show`
- `cat /proc/pressure/memory`
- Inspect the latest lines from `/var/log/zram-monitor.log`
- Inspect `/var/log/zram-monitor-incidents.log` when thresholds were expected to trigger

## Swappiness and VM comparison workflow
- Capture a baseline snapshot with `scripts/capture-swappiness-snapshot.sh`.
- Apply one runtime test value with `scripts/set-swappiness.sh`, `scripts/set-page-cluster.sh`, `scripts/set-zswap-enabled.sh`, or use the wrappers `scripts/run-swappiness-benchmark.sh`, `scripts/run-page-cluster-benchmark.sh`, and `scripts/run-zswap-benchmark.sh` to apply a value and capture a stressed snapshot under a bounded workload.
- Wait for normal usage or trigger one monitor sample.
- Capture a second snapshot.
- Compare the two snapshots with `scripts/compare-swappiness-snapshots.sh`.
- Persist only the winner with the matching persistent helper where one exists, and use the same persistent helper with another value as rollback.

## Story level testing guidance
- **Planning stories**: validate JSON and Markdown structure, plus presence of expected files.
- **Deployment asset stories**: validate syntax of unit files and logrotate config, then verify the installation instructions against a disposable target path or dry run helper.
- **Monitor logic stories**: validate shell syntax, threshold behavior, and log formatting. `scripts/zram-monitor.sh` now accepts `LOG_FILE` and `INCIDENT_LOG` overrides, so runtime behavior can be exercised without writing to `/var/log`.
- **Documentation stories**: check that README and context docs agree on canonical file paths and install steps.

## Known gaps
- No dedicated dry run mode for the monitor script.
- No fixture based test for threshold logic.
- No validation script for the documented ZRAM alignment flow.
- No automated check that `README.md` and versioned deployment assets stay synchronized.

## Next testing improvement target
Introduce a lightweight validation script that can run locally without root, uses the `LOG_FILE` and `INCIDENT_LOG` overrides, and exercises both the no alert and alert branches of the monitor logic.

## Related resources
- [Development workflow](./development-workflow.md)
- [Data flow](./data-flow.md)
- [GSD current state](./planning_gsd/STATE.md)
