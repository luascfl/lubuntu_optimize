# GSD state

## Snapshot
- Date: 2026-05-17
- Phase: execution ready
- Workflow phase: `E`
- Active milestone: `M2. Version deployment assets`
- Next milestone after M2: `M3. Add validation harness`
- Ralph story selected for next implementation cycle: `US-002`

## Execution gate
Execution is blocked if any canonical planning file is missing:
- `AGENTS.md`
- `GEMINI.md`
- `.context/docs/planning_gsd/PROJECT.md`
- `.context/docs/planning_gsd/STATE.md`
- `.context/prd_ralph/README.md`
- `.context/prd_ralph/prd.json`
- `.context/workflow/status.yaml`

When blocked, stop and restore missing files before selecting or running any story.

## Observed repository state
- `README.md` describes a manual ZRAM alignment and monitoring flow.
- `scripts/zram-monitor.sh` and `zram-monitor.sh` are duplicate monitor scripts.
- `scripts/install-zram-monitor.sh` installs the canonical monitor script into `/usr/local/bin/zram-monitor.sh`.
- `scripts/set-swappiness.sh` applies bounded runtime swappiness values, `scripts/set-swappiness-persistent.sh` persists a chosen value, and the snapshot helpers capture and compare trial evidence.
- The README still references `systemd` timer and `logrotate` assets that are not versioned in the repository.
- `toggle-passwordless-sudo.sh` exists at the repository root to toggle passwordless sudo in `tuning` or `full` mode.
- `US-001` is marked `done` in `.context/prd_ralph/prd.json` after a no commit Ralph bootstrap run.
- The workspace is not a Git repository in its current filesystem state.

## Milestone status
### M1. Planning baseline
Status: complete

Evidence:
- `.context/docs/planning_gsd/PROJECT.md` exists.
- `.context/docs/planning_gsd/STATE.md` exists.
- `.context/prd_ralph/README.md` and `.context/prd_ralph/prd.json` exist.
- `.context/workflow/status.yaml` exists and is in phase `E`.
- Local `AGENTS.md` and `GEMINI.md` now point execution back to the canonical planning surface.

### M2. Version deployment assets
Status: ready to execute

Goal:
Add repository managed `systemd` and `logrotate` assets plus installation documentation so the monitor stack can be deployed from versioned files instead of README prose alone.

## Host tuning iteration 1 baseline
Date: 2026-05-17

Baseline captured:
- `free -m`: 1562 MiB available, 1863 MiB swap used total.
- `swapon --show`: `/dev/zram0` 2.2 GiB with 1.7 GiB used, `/swapfile` 8 GiB with 82.4 MiB used.
- `zramctl`: `lz4`, `DISKSIZE 2.2G`, `DATA 1.7G`, `COMPR 378.6M`, `TOTAL 399.9M`.
- `/proc/pressure/memory`: `some avg60=1.82`, `full avg60=0.96`.
- `vm.swappiness = 110`.
- `/etc/default/zramswap`: `ALGO=lz4`, `PERCENT=60`, `SIZE=512`, `PRIORITY=180`.
- `/etc/default/earlyoom`: `-m 8 -s 55` with protected process list.
- `zram-monitor.timer`: installed but `disabled` and `inactive`.
- `zram-monitor.service`: installed but `inactive`.
- `/var/log/zram-monitor.log`: present but effectively empty.
- `journalctl -u zram-monitor.service -u zram-monitor.timer`: no entries.
- `sudo -n true`: failed because interactive authentication is required.

Decision for iteration 1:
- No host configuration change applied.
- Reason: monitoring is not active, there is no time series yet, and this session does not have non interactive sudo, so enabling the timer or changing sysctl, earlyoom, or zramswap safely is not possible from here.

Recommended next manual host action before iteration 2:
- Run `sudo systemctl enable --now zram-monitor.timer`
- Run `sudo systemctl start zram-monitor.service`
- Use the machine normally long enough to collect samples, then re-run analysis.

Rollback for that manual activation:
- `sudo systemctl stop zram-monitor.timer`
- `sudo systemctl disable zram-monitor.timer`


## Host tuning iteration 2
Date: 2026-05-17

Fresh evidence captured after enabling the timer:
- `zram-monitor.timer`: `active`, `enabled`.
- `zram-monitor.service`: runs successfully as a oneshot.
- `/var/log/zram-monitor.log` now contains repeated samples.
- Sample at `2026-05-17T13:44:49-03:00`: `899 MiB` available, `2152 MiB` swap used, alert `high-swap-usage`.
- Sample at `2026-05-17T13:47:38-03:00`: `990 MiB` available, `2165 MiB` swap used, alert `high-swap-usage`.
- Sample at `2026-05-17T13:49:30-03:00`: `939 MiB` available, `2160 MiB` swap used, `some avg60=0.05`, `full avg60=0.02`, alert `high-swap-usage`.

Comparison against iteration 1:
- Available memory is lower than the first baseline, but still well above the 400 MiB operational floor.
- Swap usage remains stably above 2 GiB.
- Pressure readings from the new monitor samples are currently low, so the machine is not under immediate reclaim distress even with high swap occupancy.

Change applied in iteration 2:
- No host tuning parameter such as `vm.swappiness`, `earlyoom`, or ZRAM size was changed yet.
- One safe observability change was applied instead: the monitor now logs `/proc/pressure/memory`, and the updated script was reinstalled to `/usr/local/bin/zram-monitor.sh`.

Rollback for the observability change:
- Remove the `PRESSURE_FILE` variable and the `/proc/pressure/memory` logging block from `scripts/zram-monitor.sh` and `zram-monitor.sh`.
- Reinstall the previous content with `sudo -n ./scripts/install-zram-monitor.sh`.

Decision for iteration 2:
- Defer host tuning changes for now.
- Reason: with only a few samples, high swap usage alone is not enough evidence to lower `vm.swappiness` or change ZRAM, because memory pressure is currently low and available memory remains acceptable.

## Host tuning iteration 3
Date: 2026-05-17

Fresh evidence captured after several timer runs:
- Current `free -m`: `889 MiB` available.
- Current `swapon --show`: `2472 MiB` swap used total, with `/swapfile` at `515.8 MiB` and `/dev/zram0` at `1.9 GiB`.
- Current `/proc/pressure/memory`: `some avg60=3.31`, `full avg60=2.41`.
- Logged samples reached `2308 MiB` swap used at `2026-05-17T19:40:54-03:00`, `2410 MiB` at `2026-05-17T19:51:00-03:00`, and `2628 MiB` at `2026-05-17T20:01:01-03:00`.
- Logged pressure reached `some avg60=7.62`, `full avg60=4.50` at `2026-05-17T20:01:01-03:00`.
- No OOM or earlyoom events were found in the recent journal slice.

Comparison against iteration 2:
- Swap usage stayed high for hours instead of dropping after the first few samples.
- Pressure is now clearly above the earlier near-zero readings, though still short of outright collapse.
- The evidence supports a cautious swappiness test, but the active sudoers entry on the host does not yet include the new helper.

Change applied in iteration 3:
- No host tuning parameter was changed yet.
- One tooling change was applied instead: added `scripts/set-swappiness.sh` and updated `toggle-passwordless-sudo.sh` so the `tuning` profile can whitelist exact swappiness values `60`, `80`, `90`, `100`, and `110`.

Rollback for the tooling change:
- Remove `scripts/set-swappiness.sh`.
- Remove the `scripts/set-swappiness.sh <value>` entries from `toggle-passwordless-sudo.sh`.

Decision for iteration 3:
- Defer the swappiness change until the refreshed sudoers profile is installed on the host.
- Attempting `sudo -n ./scripts/set-swappiness.sh 90` currently fails with `sudo-rs: interactive authentication is required`.
- Next host action: run `sudo ./toggle-passwordless-sudo.sh enable --profile tuning` again, then the next iteration can test `sudo -n ./scripts/set-swappiness.sh 90` with rollback to `110`.

## Host tuning iteration 4
Date: 2026-05-17

Fresh evidence captured after another monitor cycle:
- Current `free -m`: `889 MiB` available.
- Current `swapon --show`: `2472 MiB` swap used total, with `/swapfile` at `515.8 MiB` and `/dev/zram0` at `1.9 GiB`.
- Current `/proc/pressure/memory`: `some avg60=3.31`, `full avg60=2.41`.
- The latest logged sample at `2026-05-17T20:01:01-03:00` reached `2628 MiB` swap used with `some avg60=7.62` and `full avg60=4.50`.
- No OOM or earlyoom events were found in the recent journal slice.

Comparison against iteration 3:
- The host still shows sustained high swap occupancy and moderate reclaim pressure.
- This remains enough evidence for a cautious `swappiness` test.
- The blocker is still privilege routing, not lack of signal.

Change applied in iteration 4:
- No host tuning parameter was changed.
- No additional repository helper was needed.

Rollback:
- No host change was applied, so no rollback was needed.

Decision for iteration 4:
- Defer the `swappiness` test again because the active host sudoers entry is still stale.
- `sudo -n -l` shows the old `vm.swappiness=*` rule and does not list `scripts/set-swappiness.sh`.
- Attempting `sudo -n ./scripts/set-swappiness.sh 90` still fails with `sudo-rs: interactive authentication is required`.
- Next host action remains: run `sudo ./toggle-passwordless-sudo.sh enable --profile tuning` again, then retry the swappiness test with rollback to `110`.

## Host tuning iteration 5
Date: 2026-05-17

Fresh evidence captured after another monitor cycle:
- Current `free -m`: `581 MiB` available.
- Current `swapon --show`: `2288 MiB` swap used total, with `/swapfile` at `476.4 MiB` and `/dev/zram0` at `1.8 GiB`.
- Current `/proc/pressure/memory`: `some avg60=0.60`, `full avg60=0.36`.
- The latest logged sample at `2026-05-17T20:11:01-03:00` reached `2143 MiB` swap used and emitted both `low-memory-available (446MiB)` and `high-swap-usage (2143MiB)`.
- No OOM or earlyoom events were found in the recent journal slice.

Comparison against iteration 4:
- Swap remains well above the desired operating target even when pressure later cools down.
- A low-memory alert has now appeared in the monitor history, which strengthens the case for a controlled swappiness trial.
- The blocker is still the unchanged host sudoers entry, not missing evidence.

Change applied in iteration 5:
- No host tuning parameter was changed.
- No repository code change was needed beyond recording the new evidence.

Rollback:
- No host change was applied, so no rollback was needed.

Decision for iteration 5:
- Stop here until the host sudoers entry is refreshed.
- This is now multiple consecutive iterations without a host-side gain because `sudo -n ./scripts/set-swappiness.sh 90` is still blocked.
- `sudo -n -l` still shows the stale `vm.swappiness=*` rule and does not list `scripts/set-swappiness.sh`.
- Required manual action remains: run `sudo ./toggle-passwordless-sudo.sh enable --profile tuning`, then retry the swappiness test with rollback to `110`.

## Host tuning iteration 6
Date: 2026-05-18

Fresh evidence captured after the manual `enable --profile tuning` rerun:
- Current `free -m`: `862 MiB` available.
- Current `swapon --show`: `3069 MiB` swap used total, with `/swapfile` at `1.0 GiB` and `/dev/zram0` at `2.0 GiB`.
- Current `/proc/pressure/memory`: `some avg60=0.58`, `full avg60=0.53`.
- The latest logged sample at `2026-05-18T14:16:33-03:00` reached `2872 MiB` swap used with `some avg60=2.44`, `full avg60=2.18`.
- No OOM or earlyoom events were found in the recent journal slice.

Comparison against iteration 5:
- Swap usage increased further and now exceeds 3 GiB at the current point-in-time check.
- Available memory recovered relative to the low-memory alert sample, but the system is still carrying far more swap than the target.
- The swappiness trial remains the next rational change if privilege routing can be trusted.

Change applied in iteration 6:
- No host tuning parameter was changed.
- No repository code change was needed.

Rollback:
- No host change was applied, so no rollback was needed.

Decision for iteration 6:
- Stop again until the privilege mismatch is resolved.
- Even after the manual `sudo ./toggle-passwordless-sudo.sh enable --profile tuning`, `sudo -n -l` still reports the old sudoers grant and does not list `scripts/set-swappiness.sh`.
- Because of that mismatch, the controlled swappiness trial is still blocked.
- Next manual diagnostic step should verify the active sudoers file contents and, if needed, run a full disable plus enable cycle before retrying the test.

## Host tuning iteration 7
Date: 2026-05-18

Fresh evidence captured before the change:
- `vm.swappiness = 110`.
- `free -m`: `834 MiB` available.
- `swapon --show`: `3096 MiB` swap used total, with `/swapfile` at `1022.1 MiB` and `/dev/zram0` at `2.0 GiB`.
- `/proc/pressure/memory`: `some avg60=21.18`, `full avg60=15.44`.

Comparison against iteration 6:
- The privilege mismatch was resolved enough to run `sudo -n ./scripts/set-swappiness.sh 90`.
- Swap and pressure were materially worse than the prior checkpoint, so a cautious `swappiness` reduction was justified.

Change applied in iteration 7:
- Applied `sudo -n ./scripts/set-swappiness.sh 90`.

Rollback:
- `sudo -n ./scripts/set-swappiness.sh 110`

Evidence after the change and one follow-up sample:
- `vm.swappiness = 90`.
- `free -m`: `642 MiB` available.
- `swapon --show`: `2708 MiB` swap used total, with `/swapfile` at `1015.7 MiB` and `/dev/zram0` at `1.7 GiB`.
- `/proc/pressure/memory`: `some avg60=4.72`, `full avg60=3.96`.
- The monitor sample at `2026-05-18T14:44:06-03:00` recorded `2710 MiB` swap used with the same reduced pressure profile.

Decision for iteration 7:
- Keep `vm.swappiness=90` for now.
- Reason: swap dropped by roughly `388 MiB` and pressure dropped sharply, while available memory stayed above the `400 MiB` floor.
- Next step is observation, not another config change.

## Host tuning iteration 8
Date: 2026-05-19

Verification result:
- Current `vm.swappiness` is `110`, so the earlier `90` trial is not active anymore.
- Current `free -m`: `1135 MiB` available in the latest forced monitor sample.
- Current `swapon --show`: `1134 MiB` swap used total, with `/swapfile` at `40 MiB` and `/dev/zram0` at `1.1 GiB`.
- Current `/proc/pressure/memory`: `some avg60=0.21`, `full avg60=0.17`.
- The latest forced monitor sample at `2026-05-19T20:39:45-03:00` reported no low-memory alert and much lower pressure than the stressed sample from iteration 7.

Comparison against iteration 7:
- The temporary `swappiness=90` test did improve swap and pressure at the time it was applied.
- The current system is healthier than the stressed checkpoint, but that improvement cannot be attributed to `swappiness=90` anymore because the host is back on `110`.
- The present low pressure and lower swap show the workload changed or memory was reclaimed, but the `90` setting itself did not persist as the active runtime value.

Change applied in iteration 8:
- No host configuration change was applied.
- This iteration only verified the current runtime state.

Rollback:
- None. No change was made in this verification pass.

Decision for iteration 8:
- The `90` trial did work as a short-term runtime test, but it is not currently in effect.
- If you want to re-run the same test, use `sudo -n ./scripts/set-swappiness.sh 90`.
- If you want the current host state preserved, do nothing now and keep observing the monitor.

## Host tuning iteration 9
Date: 2026-05-21

Fresh evidence captured before the benchmark:
- Current `vm.swappiness = 110`.
- `free -m`: `1054 MiB` available.
- `swapon --show`: `850 MiB` swap used total, all on `/dev/zram0`, with `/swapfile` at `0 B`.
- `/proc/pressure/memory`: `some avg60=0.02`, `full avg60=0.02`.

Benchmark design:
- Added a bounded memory workload and a benchmark wrapper so each swappiness value is tested under the same pressure pattern.
- Ran `scripts/run-swappiness-benchmark.sh` with `768 MiB` workload, `8` seconds of warmup, and `40` seconds of hold time for `110`, `90`, `80`, and `60`.

Evidence from the benchmark:
- `110 -> 90`: memory available improved from `580 MiB` to `697 MiB`, swap dropped from `1252 MiB` to `1176 MiB`, `pressure some avg60` dropped from `2.43` to `1.91`, and `pressure full avg60` dropped from `1.74` to `1.22`.
- `90 -> 80`: memory available stayed effectively flat, `697 MiB` to `696 MiB`, swap dropped from `1176 MiB` to `1170 MiB`, `pressure some avg60` dropped from `1.91` to `0.70`, and `pressure full avg60` dropped from `1.22` to `0.44`.
- `80 -> 60`: swap stayed flat at `1170 MiB`, pressure improved again, but available memory dropped from `696 MiB` to `654 MiB`, so the result was mixed rather than clearly better.

Change applied in iteration 9:
- Applied `sudo -n ./scripts/set-swappiness.sh 80` as the best runtime value from the benchmark set.

Rollback:
- Runtime rollback: `sudo -n ./scripts/set-swappiness.sh 110`
- Persistent rollback after enabling the helper: `sudo -n ./scripts/set-swappiness-persistent.sh 110`

Decision for iteration 9:
- Choose `80` as the current best value from the tested set `110`, `90`, `80`, and `60`.
- Keep `80` active at runtime now.
- To persist it, the host needs one more `sudo ./toggle-passwordless-sudo.sh enable --profile tuning` run so the active sudoers file includes `scripts/set-swappiness-persistent.sh`, then apply `sudo -n ./scripts/set-swappiness-persistent.sh 80`.

## Host tuning iteration 10
Date: 2026-05-21

Fresh evidence captured before the persistence attempt:
- Current `vm.swappiness = 80`.
- `/etc/sysctl.d/99-lubuntu-optimize-swappiness.conf` is absent.
- `free -m`: `1338 MiB` available.
- `swapon --show`: `1147 MiB` swap used total, with `/swapfile` at `0 B` and `/dev/zram0` at `1.1 GiB`.
- `/proc/pressure/memory`: `some avg60=0.38`, `full avg60=0.25`.

Change applied in iteration 10:
- No repository code change was needed.
- Attempted `sudo -n ./scripts/set-swappiness-persistent.sh 80`, but the host denied it with `sudo-rs: interactive authentication is required`.

Rollback:
- None. The persistent helper never ran, so no host file was created and no extra rollback is needed beyond the existing runtime rollback `sudo -n ./scripts/set-swappiness.sh 110`.

Decision for iteration 10:
- Keep `80` active only at runtime for now.
- The host-side passwordless sudo profile is still stale for the persistent helper, even though the runtime helper works.
- The next required manual action is to run `sudo ./toggle-passwordless-sudo.sh enable --profile tuning` again and confirm `sudo -n -l` now lists `scripts/set-swappiness-persistent.sh 80`, then retry persistence.

## Host tuning iteration 11
Date: 2026-05-21

Manual persistence result:
- `sudo -n /home/lucas/Downloads/lubuntu_optimize/scripts/set-swappiness-persistent.sh 80` succeeded.
- `sysctl vm.swappiness` returned `80`.
- `/etc/sysctl.d/99-lubuntu-optimize-swappiness.conf` now exists and contains `vm.swappiness=80`.

Interpretation:
- The final chosen value `80` is now active both at runtime and in persistent host configuration.
- The visible `sudo -l` output the user captured still did not enumerate the persistent helper, so the sudoers display remains inconsistent with the observed execution path.
- That inconsistency no longer blocks the optimization target, but it is worth cleaning up later if the passwordless profile needs to stay self-documenting.

Decision for iteration 11:
- Optimization target reached for swappiness.
- Keep `80` as the persisted setting.
- Rollback remains `sudo -n /home/lucas/Downloads/lubuntu_optimize/scripts/set-swappiness-persistent.sh 110`.

## Host tuning iteration 12
Date: 2026-05-21

Fine-grained benchmark result:
- Ran a second benchmark sweep around the previous winner, testing `75`, `83`, `85`, `87`, `89`, and `90` under the same bounded workload.
- `80 -> 75` was mixed: more available memory, but slightly more swap.
- `80 -> 85` was also mixed: slightly better pressure, but slightly more swap.
- `85 -> 83` improved both swap and pressure while preserving the memory floor.
- `87 -> 89` improved swap and pressure again while preserving the memory floor.
- `89 -> 90` regressed, increasing swap and pressure.

Change applied in iteration 12:
- Applied and persisted `vm.swappiness = 89`.

Current persisted state:
- `sysctl vm.swappiness` returns `89`.
- `/etc/sysctl.d/99-lubuntu-optimize-swappiness.conf` exists and contains `vm.swappiness=89`.
- A fresh monitor sample under the final setting showed `1498 MiB` swap used, `1530 MiB` available memory, and `some avg60=0.00`, `full avg60=0.00`.

Rollback:
- `sudo -n /home/lucas/Downloads/lubuntu_optimize/scripts/set-swappiness-persistent.sh 110`

Decision for iteration 12:
- Replace the earlier `80` result with `89` as the final swappiness winner.
- Keep `89` as the persisted notebook setting.

## Host tuning iteration 13
Date: 2026-05-21

Further optimization project result:
- The current persisted winner remains `vm.swappiness = 89`.
- The next safe tuning frontier was `vm.page-cluster`, with the host starting value at `0`.
- `vfs_cache_pressure` remains `50`.

Project changes prepared for the next step:
- Added runtime and persistent `page-cluster` helpers.
- Added a generic benchmark runner plus a dedicated `run-page-cluster-benchmark.sh` wrapper.
- Extended the snapshot and comparison tooling so the next experiment can compare `page-cluster` values under the same workload pattern used for the swappiness decision.

Host-side result:
- The tuning sudoers profile was refreshed and the page-cluster helpers now run passwordlessly.
- Benchmarks covered `page-cluster` values `0`, `1`, `2`, and `3`.
- Value `2` produced the best tested result: compared with `0`, it reduced swap from `1318 MiB` to `1309 MiB` and reduced pressure from `some avg60=0.35` / `full avg60=0.09` to `some avg60=0.22` / `full avg60=0.04`, while keeping more than `1 GiB` available memory.
- Value `3` regressed badly, raising swap to `1608 MiB` and pressure to `some avg60=5.07` / `full avg60=1.11`.

Decision for iteration 13:
- Persist `vm.page-cluster = 2` as the next optimization win after swappiness.
- Rollback remains `sudo -n /home/lucas/Downloads/lubuntu_optimize/scripts/set-page-cluster-persistent.sh 0`.

## Host tuning iteration 14
Date: 2026-05-21

Zswap preparation and benchmark result:
- Confirmed from the kernel admin guide that zswap can be enabled and disabled at runtime through `/sys/module/zswap/parameters/enabled`.
- Current host baseline before the benchmark was `zswap = N`, compressor `lzo`, zpool `zsmalloc`, and `max_pool_percent = 20`.
- Added `scripts/set-zswap-enabled.sh` and `scripts/run-zswap-benchmark.sh` so zswap could be benchmarked under the same workload and snapshot workflow as the other VM knobs.

Benchmark outcome:
- `zswap=0` versus `zswap=1` was tested under the same bounded workload.
- Enabling zswap increased available memory from `410 MiB` to `650 MiB`, but it also increased total swap from `1227 MiB` to `1441 MiB`.
- Pressure regressed sharply when zswap was enabled, from `some avg60=2.20` / `full avg60=1.43` to `some avg60=7.04` / `full avg60=4.41`.

Decision for iteration 14:
- Keep `zswap` disabled.
- Rollback remains `sudo -n ./scripts/set-zswap-enabled.sh 0`.
- No host-side persistent change is needed because the current and final zswap state is already disabled.
## Passwordless sudo helper change
Date: 2026-05-17

Implemented:
- Added `toggle-passwordless-sudo.sh` at the repository root.
- Default profile `tuning` writes a restricted sudoers file for `zram-monitor`, `zramswap`, `earlyoom`, the monitor install helper, the runtime and persistent swappiness helpers, the runtime and persistent page-cluster helpers, and exact timer lifecycle commands including `enable --now`.
- Optional profile `full` writes `NOPASSWD: ALL` for the selected user.
- The script supports `enable`, `disable`, and `status`.

Operational notes:
- Re-run `sudo ./toggle-passwordless-sudo.sh enable --profile tuning` after helper changes so `/etc/sudoers.d/99-omp-passwordless-<usuário>` is regenerated from the latest script.
- The repository is now writable by the current user again, so `README.md` and the scripts directory can be updated normally.
- `sudo -n -l` now shows the swappiness helpers and page-cluster helpers without pinning exact VM values in the sudoers entry.

## Monitor script and install helper change
Date: 2026-05-17

Implemented:
- Fixed the dash compatibility bug in both repository copies of `zram-monitor.sh` by using `printf --` for lines that begin with `-`.
- Added `LOG_FILE` and `INCIDENT_LOG` environment overrides so the monitor can be exercised without writing to `/var/log`.
- Added `scripts/install-zram-monitor.sh` to install the canonical `scripts/zram-monitor.sh` into `/usr/local/bin/zram-monitor.sh`.

Host state after refreshing sudoers and reinstalling the monitor:
- `sudo ./toggle-passwordless-sudo.sh enable --profile tuning` succeeded.
- `sudo -n ./scripts/install-zram-monitor.sh` succeeded.
- `sudo -n systemctl enable --now zram-monitor.timer` succeeded.
- `sudo -n systemctl start zram-monitor.service` succeeded.


## Swappiness comparison and persistence tooling change
Date: 2026-05-19

Implemented:
- Added `scripts/capture-swappiness-snapshot.sh` to capture structured before and after snapshots for a swappiness experiment.
- Added `scripts/compare-swappiness-snapshots.sh` to compare two snapshots and print a compact assessment.
- Added `scripts/set-swappiness-persistent.sh` to write `vm.swappiness` into `/etc/sysctl.d/99-lubuntu-optimize-swappiness.conf` and apply the same value immediately.
- Updated `toggle-passwordless-sudo.sh` so the `tuning` profile can call both swappiness helpers without pinning exact test values in the sudoers entry.

Operational notes:
- `scripts/capture-swappiness-snapshot.sh` and `scripts/compare-swappiness-snapshots.sh` run without root.
- `scripts/set-swappiness-persistent.sh` needs sudo because it writes into `/etc/sysctl.d/`.
- The swappiness helpers themselves enforce the accepted `0..200` numeric range, so the sudoers entry no longer needs to enumerate individual values.
- Use the same persistent helper with another value, such as `110`, as a concrete rollback path.

## Further VM tuning project change
Date: 2026-05-21

Implemented:
- Added `scripts/set-page-cluster.sh` and `scripts/set-page-cluster-persistent.sh` to manage `vm.page-cluster` with a validated `0..8` range.
- Added `scripts/run-kernel-memory-benchmark.sh` as a generic benchmark orchestrator for any validated VM helper.
- Rewrote `scripts/run-swappiness-benchmark.sh` as a thin wrapper around the generic benchmark runner and added `scripts/run-page-cluster-benchmark.sh`.
- Extended `scripts/capture-swappiness-snapshot.sh` with `page_cluster`, `vfs_cache_pressure`, and `zswap` fields so future AI-driven experiments have richer context.
- Updated `scripts/compare-swappiness-snapshots.sh` so it reports `page-cluster` and `vfs_cache_pressure` alongside the swap and PSI deltas.

Operational notes:
- The next safe optimization frontier after `swappiness=89` is `page-cluster`, but the host has not yet rerun `sudo ./toggle-passwordless-sudo.sh enable --profile tuning` since those helpers were added.
- The current project is therefore ready for the next experiment, but the host-side `page-cluster` test remains blocked until the tuning sudoers file is refreshed.
## Recommended next execution story
### US-002, Version deployment assets
Why this story next:
- It closes the largest gap between documented behavior and versioned artifacts.
- It reduces host drift risk immediately.
- It keeps the scope small enough for a single story cycle.

Definition of done for the cycle:
- Add versioned files for the monitor service, timer, and logrotate configuration.
- Add installation steps or an install helper for those files.
- Validate the new assets with story specific commands and update `README.md` plus `.context/docs/`.

## Validation evidence captured for bootstrap
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`
- `ralph build 1 --prd .context/prd_ralph/prd.json --no-commit`

## Validation evidence captured for tuning iteration 1
- `free -m`
- `swapon --show`
- `zramctl`
- `cat /proc/pressure/memory`
- `sysctl vm.swappiness`
- `systemctl status zram-monitor.timer`
- `systemctl status zram-monitor.service`
- `journalctl -u zram-monitor.service -u zram-monitor.timer --no-pager -n 20`
- `sudo -n true`

## Validation evidence captured for passwordless helper
- `dash -n toggle-passwordless-sudo.sh`
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`
- `SUDOERS_DIR=$(mktemp -d) ./toggle-passwordless-sudo.sh enable --user lucas --profile tuning`
- `SUDOERS_DIR=<tmpdir> ./toggle-passwordless-sudo.sh status --user lucas`
- `SUDOERS_DIR=<tmpdir> ./toggle-passwordless-sudo.sh disable --user lucas`
- `SUDOERS_DIR=<tmpdir> ./toggle-passwordless-sudo.sh enable --user lucas --profile full`
- `sudo -n systemctl enable zram-monitor.timer`
- `sudo -n systemctl start zram-monitor.timer`
- `sudo -n systemctl stop zram-monitor.timer`
- `sudo -n systemctl disable zram-monitor.timer`
- `systemctl status zram-monitor.service --no-pager`

## Validation evidence captured for monitor fix and install helper
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `dash -n scripts/install-zram-monitor.sh`
- `dash -n toggle-passwordless-sudo.sh`
- `LOG_FILE=<tmp> INCIDENT_LOG=<tmp> ./scripts/zram-monitor.sh`
- `DEST_SCRIPT=<tmp> ./scripts/install-zram-monitor.sh`
- `cmp scripts/zram-monitor.sh <tmp-installed-copy>`
- `SUDOERS_DIR=<tmpdir> ./toggle-passwordless-sudo.sh enable --user lucas --profile tuning`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Validation evidence captured for host monitor activation
- `sudo -n ./scripts/install-zram-monitor.sh`
- `sudo -n systemctl enable --now zram-monitor.timer`
- `sudo -n systemctl start zram-monitor.service`
- `systemctl status zram-monitor.service --no-pager`
- `systemctl status zram-monitor.timer --no-pager`
- `tail -n 40 /var/log/zram-monitor.log`

## Validation evidence captured for tuning iteration 3
- `free -m`
- `swapon --show`
- `zramctl`
- `cat /proc/pressure/memory`
- `systemctl status zram-monitor.timer --no-pager`
- `systemctl status zram-monitor.service --no-pager`
- `tail -n 80 /var/log/zram-monitor.log`
- `journalctl -b --no-pager -n 120`
- `dash -n scripts/set-swappiness.sh`
- `dash -n toggle-passwordless-sudo.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`
- `SUDOERS_DIR=<tmpdir> ./toggle-passwordless-sudo.sh enable --user lucas --profile tuning`
- `sudo -n -l`

## Validation evidence captured for tuning iteration 4
- `free -m`
- `swapon --show`
- `zramctl`
- `cat /proc/pressure/memory`
- `systemctl status zram-monitor.timer --no-pager`
- `systemctl status zram-monitor.service --no-pager`
- `tail -n 80 /var/log/zram-monitor.log`
- `journalctl -b --no-pager -n 120`
- `sudo -n -l`
- `sudo -n ./scripts/set-swappiness.sh 90`
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `dash -n scripts/install-zram-monitor.sh`
- `dash -n toggle-passwordless-sudo.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Validation evidence captured for tuning iteration 5
- `free -m`
- `swapon --show`
- `zramctl`
- `cat /proc/pressure/memory`
- `systemctl status zram-monitor.timer --no-pager`
- `systemctl status zram-monitor.service --no-pager`
- `tail -n 80 /var/log/zram-monitor.log`
- `journalctl -b --no-pager -n 120`
- `sudo -n -l`
- `sudo -n ./scripts/set-swappiness.sh 90`
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `dash -n scripts/install-zram-monitor.sh`
- `dash -n toggle-passwordless-sudo.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Validation evidence captured for tuning iteration 6
- `free -m`
- `swapon --show`
- `zramctl`
- `cat /proc/pressure/memory`
- `systemctl status zram-monitor.timer --no-pager`
- `systemctl status zram-monitor.service --no-pager`
- `tail -n 80 /var/log/zram-monitor.log`
- `journalctl -b --no-pager -n 120`
- `sudo -n -l`
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `dash -n scripts/install-zram-monitor.sh`
- `dash -n toggle-passwordless-sudo.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Validation evidence captured for tuning iteration 7
- `free -m`
- `swapon --show`
- `zramctl`
- `cat /proc/pressure/memory`
- `sudo -n -l`
- `sudo -n ./scripts/set-swappiness.sh 90`
- `sudo -n systemctl start zram-monitor.service`
- `tail -n 80 /var/log/zram-monitor.log`
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `dash -n scripts/install-zram-monitor.sh`
- `dash -n toggle-passwordless-sudo.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`


## Validation evidence captured for tuning iteration 8
- `sysctl vm.swappiness`
- `free -m`
- `swapon --show`
- `zramctl`
- `cat /proc/pressure/memory`
- `sudo -n systemctl start zram-monitor.service`
- `tail -n 80 /var/log/zram-monitor.log`
- `sudo -n -l`
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `dash -n scripts/install-zram-monitor.sh`
- `dash -n toggle-passwordless-sudo.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Validation evidence captured for swappiness tooling
- `dash -n scripts/capture-swappiness-snapshot.sh`
- `dash -n scripts/compare-swappiness-snapshots.sh`
- `dash -n scripts/set-swappiness-persistent.sh`
- `./scripts/capture-swappiness-snapshot.sh baseline <tmp-before>`
- `./scripts/capture-swappiness-snapshot.sh trial <tmp-after>`
- `./scripts/compare-swappiness-snapshots.sh <tmp-before> <tmp-after>`
- `CONF_FILE=<tmp> SYSCTL_BIN=<mock> ./scripts/set-swappiness-persistent.sh 90`
- `SUDOERS_DIR=<tmpdir> ./toggle-passwordless-sudo.sh enable --user lucas --profile tuning`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Validation evidence captured for tuning iteration 9
- `dash -n scripts/run-memory-pressure-workload.sh`
- `dash -n scripts/run-swappiness-benchmark.sh`
- `./scripts/run-memory-pressure-workload.sh 32 2`
- `./scripts/run-swappiness-benchmark.sh 110 sw110 <bench-dir> 768 8 40`
- `./scripts/run-swappiness-benchmark.sh 90 sw90 <bench-dir> 768 8 40`
- `./scripts/run-swappiness-benchmark.sh 80 sw80 <bench-dir> 768 8 40`
- `./scripts/run-swappiness-benchmark.sh 60 sw60 <bench-dir> 768 8 40`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/sw110.snapshot.txt <bench-dir>/sw90.snapshot.txt`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/sw90.snapshot.txt <bench-dir>/sw80.snapshot.txt`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/sw80.snapshot.txt <bench-dir>/sw60.snapshot.txt`
- `sudo -n ./scripts/set-swappiness.sh 80`
- `sudo -n systemctl start zram-monitor.service`
- `sysctl vm.swappiness`
- `free -m`
- `swapon --show`
- `cat /proc/pressure/memory`
- `tail -n 80 /var/log/zram-monitor.log`
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `dash -n scripts/install-zram-monitor.sh`
- `dash -n scripts/set-swappiness.sh`
- `dash -n toggle-passwordless-sudo.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Validation evidence captured for tuning iteration 11
- `sudo visudo -c`
- `sudo -l`
- `sudo -n /home/lucas/Downloads/lubuntu_optimize/scripts/set-swappiness-persistent.sh 80`
- `sysctl vm.swappiness`
- `cat /etc/sysctl.d/99-lubuntu-optimize-swappiness.conf`

## Validation evidence captured for relaxed swappiness sudoers
- `dash -n toggle-passwordless-sudo.sh`
- `dash -n scripts/set-swappiness.sh`
- `dash -n scripts/set-swappiness-persistent.sh`
- `SUDOERS_DIR=<tmpdir> ./toggle-passwordless-sudo.sh enable --user lucas --profile tuning`
- `python` assertion that the generated sudoers file includes `scripts/set-swappiness.sh,` and `scripts/set-swappiness-persistent.sh,`
- `python` assertion that the generated sudoers file no longer pins exact swappiness arguments
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Validation evidence captured for tuning iteration 12
- `./scripts/run-swappiness-benchmark.sh 75 sw75 <bench-dir> 768 8 40`
- `./scripts/run-swappiness-benchmark.sh 83 sw83 <bench-dir> 768 8 40`
- `./scripts/run-swappiness-benchmark.sh 85 sw85 <bench-dir> 768 8 40`
- `./scripts/run-swappiness-benchmark.sh 87 sw87 <bench-dir> 768 8 40`
- `./scripts/run-swappiness-benchmark.sh 89 sw89 <bench-dir> 768 8 40`
- `./scripts/run-swappiness-benchmark.sh 90 sw90refine <bench-dir> 768 8 40`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/sw80fine.snapshot.txt <bench-dir>/sw75.snapshot.txt`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/sw80fine.snapshot.txt <bench-dir>/sw85.snapshot.txt`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/sw85.snapshot.txt <bench-dir>/sw83.snapshot.txt`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/sw87.snapshot.txt <bench-dir>/sw89.snapshot.txt`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/sw89.snapshot.txt <bench-dir>/sw90refine.snapshot.txt`
- `sudo -n ./scripts/set-swappiness-persistent.sh 89`
- `sysctl vm.swappiness`
- `cat /etc/sysctl.d/99-lubuntu-optimize-swappiness.conf`
- `tail -n 80 /var/log/zram-monitor.log`
- `dash -n scripts/run-memory-pressure-workload.sh`
- `dash -n scripts/run-swappiness-benchmark.sh`
- `dash -n scripts/set-swappiness-persistent.sh`
- `dash -n toggle-passwordless-sudo.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Validation evidence captured for tuning iteration 13
- `cat /proc/sys/vm/page-cluster`
- `cat /proc/sys/vm/vfs_cache_pressure`
- `sudo -n ./scripts/set-page-cluster.sh 1`
- `./scripts/run-page-cluster-benchmark.sh 0 pc0 <bench-dir> 768 8 40`
- `./scripts/run-page-cluster-benchmark.sh 1 pc1 <bench-dir> 768 8 40`
- `./scripts/run-page-cluster-benchmark.sh 2 pc2 <bench-dir> 768 8 40`
- `./scripts/run-page-cluster-benchmark.sh 3 pc3 <bench-dir> 768 8 40`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/pc0.snapshot.txt <bench-dir>/pc1.snapshot.txt`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/pc1.snapshot.txt <bench-dir>/pc2.snapshot.txt`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/pc2.snapshot.txt <bench-dir>/pc3.snapshot.txt`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/pc0.snapshot.txt <bench-dir>/pc2.snapshot.txt`
- `sudo -n ./scripts/set-page-cluster-persistent.sh 2`
- `cat /etc/sysctl.d/99-lubuntu-optimize-page-cluster.conf`
- `tail -n 80 /var/log/zram-monitor.log`
- `dash -n scripts/set-page-cluster.sh`
- `dash -n scripts/set-page-cluster-persistent.sh`
- `dash -n scripts/run-kernel-memory-benchmark.sh`
- `dash -n scripts/run-page-cluster-benchmark.sh`
- `dash -n scripts/capture-swappiness-snapshot.sh`
- `dash -n scripts/compare-swappiness-snapshots.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Validation evidence captured for tuning iteration 14
- `cat /sys/module/zswap/parameters/enabled`
- `cat /sys/module/zswap/parameters/compressor`
- `cat /sys/module/zswap/parameters/max_pool_percent`
- `cat /sys/module/zswap/parameters/zpool`
- `sudo -n ./scripts/set-zswap-enabled.sh 1`
- `sudo -n ./scripts/set-zswap-enabled.sh 0`
- `./scripts/run-zswap-benchmark.sh 0 zswap0 <bench-dir> 768 8 40`
- `./scripts/run-zswap-benchmark.sh 1 zswap1 <bench-dir> 768 8 40`
- `./scripts/compare-swappiness-snapshots.sh <bench-dir>/zswap0.snapshot.txt <bench-dir>/zswap1.snapshot.txt`
- `dash -n scripts/set-zswap-enabled.sh`
- `dash -n scripts/run-zswap-benchmark.sh`
- `dash -n scripts/run-kernel-memory-benchmark.sh`
- `dash -n scripts/capture-swappiness-snapshot.sh`
- `dash -n scripts/compare-swappiness-snapshots.sh`
- `dash -n toggle-passwordless-sudo.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`
## Host app tuning iteration 15
Date: 2026-06-07

User target:
- Keep the ZapZap Flatpak for WhatsApp available in the background for sync while reducing freeze risk on the 4 GiB Lubuntu host.

Fresh evidence captured before the change:
- `free -h`: `3.7Gi` total memory, `1.0Gi` available, `822Mi` swap used on `/dev/zram0`.
- Runtime VM knobs had drifted from the documented winners: `vm.swappiness = 110` and `vm.page-cluster = 0`.
- Persistent files still contained the benchmark winners: `/etc/sysctl.d/99-lubuntu-optimize-swappiness.conf` had `vm.swappiness=89`, and `/etc/sysctl.d/99-lubuntu-optimize-page-cluster.conf` had `vm.page-cluster=2`.
- ZapZap is installed as Flatpak `com.rtosta.zapzap`.
- Flatpak background permission for `com.rtosta.zapzap` was already `yes`.
- `~/.config/autostart/com.rtosta.zapzap.desktop` existed with `Exec=flatpak run --command=zapzap com.rtosta.zapzap --hideStart`, but LXQt autostart was disabled by `X-LXQt-Autostart-disabled=true`.

Change applied:
- Re-applied and persisted the documented memory winners with `sudo -n ./scripts/set-swappiness-persistent.sh 89` and `sudo -n ./scripts/set-page-cluster-persistent.sh 2`.
- Removed `X-LXQt-Autostart-disabled=true` from `~/.config/autostart/com.rtosta.zapzap.desktop`, so ZapZap starts hidden at session login using the existing `--hideStart` command.
- Started ZapZap hidden immediately with `flatpak run --command=zapzap com.rtosta.zapzap --hideStart`.

Evidence after the change:
- `sysctl vm.swappiness vm.page-cluster` returned `89` and `2`.
- `/etc/sysctl.d/99-lubuntu-optimize-swappiness.conf` contains `vm.swappiness=89`.
- `/etc/sysctl.d/99-lubuntu-optimize-page-cluster.conf` contains `vm.page-cluster=2`.
- `free -h` showed `1.2Gi` available memory after the change.
- `flatpak permissions background` still showed `background background com.rtosta.zapzap yes 0x00`.
- Process inspection found ZapZap running hidden; the early startup footprint was about `104 MiB` RSS, and a later fully loaded check saw about `432 MiB` RSS including QtWebEngine children.

Rollback:
- Disable hidden startup again by restoring `X-LXQt-Autostart-disabled=true` in `~/.config/autostart/com.rtosta.zapzap.desktop`.
- Stop ZapZap from the tray or terminate the running Flatpak process if background sync is not desired.
- Runtime and persistent memory rollback remains `sudo -n ./scripts/set-swappiness-persistent.sh 110` and `sudo -n ./scripts/set-page-cluster-persistent.sh 0`.

Decision:
- Keep ZapZap hidden autostart enabled because it satisfies the sync target with low observed startup memory cost.
- Keep runtime `swappiness=89` and `page-cluster=2` because these are the repository's benchmarked winners and reduce freeze risk compared with the drifted runtime values.

Validation evidence captured for iteration 15:
- `sudo -n ./scripts/set-swappiness-persistent.sh 89`
- `sudo -n ./scripts/set-page-cluster-persistent.sh 2`
- `sysctl vm.swappiness vm.page-cluster`
- Read `/etc/sysctl.d/99-lubuntu-optimize-swappiness.conf`
- Read `/etc/sysctl.d/99-lubuntu-optimize-page-cluster.conf`
- `python3 -m json.tool .context/prd_ralph/prd.json`
- Process inspection through `/proc` for `zapzap` and `com.rtosta.zapzap`

## Host browser pressure iteration 16
Date: 2026-07-21

User target:
- Stop LibreWolf tabs from being closed when opening heavy web apps such as Outlook.

Evidence captured:
- Current memory before the change: `942 MiB` available, `1.2 GiB` swap used on ZRAM, `some avg60=0.33`, `full avg60=0.17`.
- Runtime VM knobs had drifted again to `vm.swappiness=110` and `vm.page-cluster=0`, while the intended persisted values are `89` and `2`.
- `journalctl -u earlyoom --since -3h` showed repeated EarlyOOM kills of LibreWolf `Isolated Web Co` and `Web Content` processes.
- Examples: at `17:30:27`, EarlyOOM killed LibreWolf content process `89871` with `VmRSS 421 MiB`; at `17:32:22`, it killed process `91367` with `VmRSS 337 MiB`.
- The active EarlyOOM thresholds were `-m 50 -s 5`, and `--prefer` explicitly included `Isolated Web Co|Web Content`, making LibreWolf tabs primary kill targets.

Change applied:
- Re-applied and persisted `vm.swappiness=89` and `vm.page-cluster=2`.
- Changed `/etc/default/earlyoom` from `-m 50 -s 5` to `-m 20 -s 5`.
- Removed `Isolated Web Co|Web Content` from EarlyOOM `--prefer`, leaving `--prefer '^(chrome|chromium|code|electron)$'`.
- Restarted `earlyoom.service`.
- Updated `README.md` to document the new EarlyOOM policy.

Validation evidence:
- `systemctl status earlyoom --no-pager -l` reports the active command with `-m 20 -s 5`.
- EarlyOOM startup log reports `sending SIGTERM when mem avail <= 20.00% and swap free <= 5.00%`.
- `sysctl vm.swappiness vm.page-cluster` reports `89` and `2`.
- `/etc/default/earlyoom` comments and `EARLYOOM_ARGS` match the new policy.
- `journalctl -u earlyoom --since '2026-07-21 17:40:43'` showed the service restart and no new kill event in the checked window.
- Final snapshot after the change: `673 MiB` available, `1.8 GiB` swap used, `some avg60=1.43`, `full avg60=0.82`.
- Project validation still passes: `dash -n scripts/zram-monitor.sh`, `dash -n zram-monitor.sh`, and `python3 -m json.tool .context/prd_ralph/prd.json`.

Decision:
- Keep the less aggressive EarlyOOM policy because the prior setting was the direct cause of repeated LibreWolf tab closures under Outlook-level web app load.
- Rollback if the whole desktop freezes instead of preserving tabs: restore `-m 50 -s 5` and add `Isolated Web Co|Web Content` back into `--prefer`, then restart `earlyoom`.


## Host freeze rollback iteration 17
Date: 2026-07-21

User report:
- The computer froze at `17:57` after the less aggressive `earlyoom` policy from iteration 16.

Evidence captured:
- `journalctl -u earlyoom` shows a boot boundary at `17:58`, so the `17:57` freeze likely forced a reboot or hard reset.
- Before the boot boundary, `earlyoom` with `-m 20 -s 5` did not kill anything after `17:40:20`; the last samples were `17:53:47` with `27.25%` memory available and `50.75%` swap free, `17:54:47` with `26.94%` memory and `48.44%` swap free, and `17:55:47` with `38.55%` memory and `29.46%` swap free.
- After reboot, runtime VM knobs were again `vm.swappiness=110` and `vm.page-cluster=0`.
- The cause of that runtime drift was found in `/etc/sysctl.d/zz-memory-guard.conf`, which still overrode the benchmarked values with `vm.swappiness=110` and `vm.page-cluster=0` after systemd-sysctl.

Change applied:
- Changed `/etc/default/earlyoom` to a preventive anti-freeze policy: `-m 40 -s 30`.
- Restored `Isolated Web Co|Web Content` in EarlyOOM `--prefer`, because preserving heavy LibreWolf tabs caused a full desktop freeze.
- Updated `/etc/sysctl.d/zz-memory-guard.conf` to `vm.swappiness=89` and `vm.page-cluster=2`, so boot no longer overrides the benchmarked values.
- Re-applied the persistent helpers and restarted `earlyoom.service`.
- Updated `README.md` to document the new tradeoff: kill the heavy tab before freezing the desktop.

Validation evidence:
- `systemctl status earlyoom --no-pager -l` reports the active command with `-m 40 -s 30` and `--prefer '^(chrome|chromium|code|electron|Isolated Web Co|Web Content)$'`.
- EarlyOOM startup log reports `sending SIGTERM when mem avail <= 40.00% and swap free <= 30.00%`.
- `sysctl vm.swappiness vm.page-cluster` reports `89` and `2`.
- `/etc/sysctl.d/zz-memory-guard.conf`, `/etc/sysctl.d/99-lubuntu-optimize-swappiness.conf`, and `/etc/sysctl.d/99-lubuntu-optimize-page-cluster.conf` all agree on the benchmarked VM values.
- Current snapshot after the change: `1.5 GiB` available, `49 MiB` swap used, and memory PSI `avg10/avg60/avg300 = 0.00`.

Decision:
- Prefer preserving the desktop over preserving a single Outlook/LibreWolf tab. On this 4 GiB host, trying to keep the tab alive crossed from “annoying tab close” into full system freeze.
- If Outlook remains necessary, the next mitigation should be reducing concurrent background services before opening it, not weakening EarlyOOM again.


## Optimization research iteration 18
Date: 2026-07-21

User question:
- "tem alguma otimização q pode ser feita ainda? pesquise."

Research scope:
- No new Ralph implementation story was executed in this pass. This was a research and triage pass against the current host state, project context, AI Coders Context map, journal evidence, and external documentation.

Findings:
- `earlyoom` acts only when both memory and swap thresholds are crossed, so the current `-m 40 -s 30` is intentionally a desktop-preservation policy rather than a tab-preservation policy.
- Official EarlyOOM documentation confirms the default behavior: it checks available memory and free swap, and by default kills when both are below 10%; thresholds are configurable by command line.
- Official zram-generator documentation confirms systemd-managed zram config can be declared in `/etc/systemd/zram-generator.conf`, with `zram-size = ram / 2` as the minimal example. Current host still uses `/etc/default/zramswap`, so migration to zram-generator is a possible future consolidation, not an immediate fix.
- ZRAM research keeps `lz4` as the safer algorithm for this CPU because it prioritizes latency and low CPU cost. This matches current host config and prior benchmark decision.
- Current process audit shows the largest non-browser memory contributors are the active OMP/Codex/Jarvis stack, rclone mounts, Docker, and user MCP servers. Before opening Outlook or Google Cloud Console, temporarily stopping optional background services may give more real headroom than more kernel tuning.
- Current failed units include `zotero-sync.service`, `hermes-gateway.service`, `webdav-koofr.service`, `snap.firmware-updater.firmware-notifier.service`, and user `cpugov-performance.service`. Failed retry loops and startup failures are candidates for cleanup, especially `zotero-sync.service`, which logged a Python `KeyError`.
- Firefox/LibreWolf memory research points to reducing the content process limit for 4 GiB systems, enabling tab unloading, and increasing session-save intervals as browser-level mitigations. These trade some isolation and convenience for lower memory pressure.

Recommended next optimization candidates:
1. Add a documented "heavy web app mode" script that stops optional services before opening Outlook/Google Cloud Console, captures memory before/after, then restores services.
2. Add a host validation story that detects sysctl override drift, especially conflicts like `/etc/sysctl.d/zz-memory-guard.conf` overriding benchmarked values.
3. Tune LibreWolf profile settings for low memory: content process limit `2` or `3`, tab unload enabled, and less frequent sessionstore writes.
4. Investigate and fix failed user/system services that waste startup time or retry resources, especially the Zotero sync `KeyError`.
5. Consider a future zram-generator migration only after deployment assets are versioned, because it changes boot-time ownership of zram setup.

Decision:
- The best immediate optimization is not another VM knob. The next safe project story should version the deployment assets and add validation around drift, then add a deliberate heavy-web-app mode. More aggressive kernel tuning now would mostly move the failure mode between tab kills and full freezes.


## Host service governance iteration 19
Date: 2026-07-21

User request:
- "coloca a governança dele no projeto aqui no lubuntu optimize: cpugov-performance.service"

Governance record:
- `cpugov-performance.service` is now documented as a governed host artifact, not as a repository-versioned deployment asset.
- Unit path: `/etc/systemd/system/cpugov-performance.service`.
- Enable path: `/etc/systemd/system/multi-user.target.wants/cpugov-performance.service`.
- Runtime command: `echo 'performance' > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`.
- Known source: manual/local unit file in `/etc/systemd/system`.
- Observed mtime: `2025-09-10 22:36:34 -0300`.
- No generator was found inside `lubuntu_optimize`; future changes must treat this as manual host drift unless a versioned asset is added deliberately.


## Host service asset iteration 20
Date: 2026-07-21

User request:
- "no caso o cpu gov deve ter um script de verificação instalação e habilitação aqui no projeto como os outros"

Change applied:
- Added versioned unit asset `systemd/cpugov-performance.service`.
- Collapsed cpugov governance to one script only: `scripts/apply-cpugov-performance-service.sh`.
- Removed the temporary split scripts `scripts/install-cpugov-performance-service.sh` and `scripts/check-cpugov-performance-service.sh` after the user clarified that cpugov must have exactly one script.
- The single script now installs the unit to `/etc/systemd/system/cpugov-performance.service`, runs `systemctl daemon-reload`, enables/starts `cpugov-performance.service`, verifies source-vs-installed unit drift, checks enabled state and last systemd result, and checks live CPU governor values under `/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`.
- Updated `toggle-passwordless-sudo.sh` tuning profile to include only `scripts/apply-cpugov-performance-service.sh` for cpugov.
- Updated `README.md` and `.context/docs/README.md` so cpugov documents one combined governance command only.
- Hardened `systemd/cpugov-performance.service` so governor write failures make the unit fail instead of being masked by the final `found` check.

Validation evidence:
- `dash -n scripts/apply-cpugov-performance-service.sh`, `dash -n toggle-passwordless-sudo.sh`, `dash -n scripts/zram-monitor.sh`, and `dash -n zram-monitor.sh` passed.
- `python3 -m json.tool .context/prd_ralph/prd.json` passed.
- Dry-run of `scripts/apply-cpugov-performance-service.sh` with temporary `DEST_UNIT`, fake `systemctl`, fake root `id`, and fake CPU governor path installed the versioned unit, invoked `daemon-reload`, invoked `enable --now cpugov-performance.service`, and verified `performance`.
- `SUDOERS_DIR=<tmp> ./toggle-passwordless-sudo.sh enable --profile tuning` passed `visudo` validation for the one-script cpugov profile.


## Passwordless sudo PTY iteration 21
Date: 2026-07-21

User request:
- "dá pra colocar o pty no toggle passwordless?"

Change applied:
- Added `--pty` to `toggle-passwordless-sudo.sh`.
- `--pty` is for non-root runs when the current agent shell cannot show an interactive sudo password prompt.
- The helper opens a visible terminal (`qterminal`, `lxterminal`, or `xterm`, or `PTY_TERMINAL` when set) and reruns the same action through `sudo`, preserving `--profile` and `--user`.
- Added `PTY_DRY_RUN=1` for safe validation of the selected terminal and generated sudo command without launching a GUI.
- Updated `README.md` with the PTY command: `./toggle-passwordless-sudo.sh enable --profile tuning --pty`.

Validation evidence:
- `PTY_DRY_RUN=1 PTY_TERMINAL=/usr/bin/qterminal ./toggle-passwordless-sudo.sh enable --profile tuning --pty` printed the visible terminal path and generated `sudo ... enable --profile tuning --user lucas` without launching a GUI.
- `SUDOERS_DIR=<tmp> ./toggle-passwordless-sudo.sh enable --profile tuning` passed `visudo` validation.
- `dash -n toggle-passwordless-sudo.sh`, `dash -n scripts/apply-cpugov-performance-service.sh`, `dash -n zram-monitor.sh`, and `dash -n scripts/zram-monitor.sh` passed.
- `python3 -m json.tool .context/prd_ralph/prd.json` passed.


## Passwordless sudo and cpugov application iteration 22
Date: 2026-07-21

User request:
- "roda aqui o toggle passwordless"

Change applied:
- Ran `./toggle-passwordless-sudo.sh enable --profile tuning --pty`; the visible terminal flow completed and regenerated the sudoers profile.
- Verified `sudo -n -l` lists the tuning profile and includes `/home/lucas/Downloads/lubuntu_optimize/scripts/apply-cpugov-performance-service.sh`.
- `sudo -n ./scripts/apply-cpugov-performance-service.sh` still failed because sudoers matches absolute command paths; reran with the absolute path.
- First cpugov apply exposed a systemd specifier bug: `printf "%s\n"` in `ExecStart` was expanded by systemd to the user's shell path. Replaced it with `printf "performance\n"`.
- Tightened the CPU glob from `cpu*` to `cpu[0-9]*` in both the unit and the verifier script to avoid matching `/sys/devices/system/cpu/cpufreq` and `/sys/devices/system/cpu/cpuidle`.

Validation evidence:
- `sudo -n /home/lucas/Downloads/lubuntu_optimize/scripts/apply-cpugov-performance-service.sh` installed and enabled `/etc/systemd/system/cpugov-performance.service`.
- The apply script reported unit file match, enabled state, `Result=success`, and all four CPU governors as `performance`.
- `systemctl is-enabled cpugov-performance.service` returned `enabled`.
- Reading `/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor` returned `performance` for CPU0 through CPU3.

## Open assumptions
- The low memory Lubuntu laptop profile remains the primary supported environment.
- Freeze evidence may add one `systemd` session-marker service beside the existing timer and flat logs when `early-oom/memory-guard.sh` is installed.
- `create_and_push_repo.sh` remains out of scope for the next implementation story.

## Freeze evidence installer iteration 23
Date: 2026-08-11

User request:
- Preserve evidence around desktop freezes, forced shutdowns, and subsequent boots for at least two sessions.

Change applied:
- Extended `early-oom/setup-memory-guard.sh` with per-minute memory snapshots that include PSI and load average. Pressure incidents also capture the largest resident processes.
- Added `memory-guard-session-log.service`. It writes an active-session marker at startup and removes it only on a clean service stop. A remaining marker at the next boot records `UNCLEAN_SHUTDOWN` and saves the previous boot's EarlyOOM and kernel-warning excerpts.
- Added a persistent journald drop-in capped at `128 MiB` and logrotate retention of 30 daily compressed rotations, bounded to `10 MiB` per active log.
- Aligned the installer defaults with the current host policy: EarlyOOM `-m 20 -s 15`, `vm.swappiness=89`, and `vm.page-cluster=2`.
- Updated `README.md` with installation, the exact forensic limits, and post-restart verification commands.
- Added `--logging-only`, which installs only the evidence scripts, timer, session service, journald retention, and logrotate policy without changing ZRAM, EarlyOOM, sysctl, or packages.

Validation evidence:
- `bash -n early-oom/setup-memory-guard.sh` passed.
- `bash early-oom/setup-memory-guard.sh --dry-run --logging-only` generated only the logging assets and service actions without writing to the host.
- The generated `memory-pressure-log.sh` and `memory-guard-session-log.sh` each passed `bash -n` and were exercised in an isolated project-local runtime test that verified snapshot capture, `UNCLEAN_SHUTDOWN`, and clean-marker removal.

Host evidence:
- Applied the non-invasive path through the visible QTerminal: `sudo bash /home/lucas/Downloads/lubuntu_optimize/early-oom/setup-memory-guard.sh --logging-only`.
- `memory-guard-session-log.service` and `memory-pressure-log.timer` are both `active` and `enabled`.
- The first session record is `2026-08-11T18:09:19-03:00 ... SESSION_STARTED`; the timer recorded PSI and load-average snapshots at 18:10 and 18:11.
- `/var/log/journal/` is populated and the configured persistent-journal limits are present.
- `systemd-analyze verify` accepted the three memory-guard units. It emitted only an unrelated pre-existing warning for `warsaw.service` using legacy `/var/run/core.pid`.

## Reorganização de Scripts e Automação (Iteration 12)
Date: $(date +%Y-%m-%d)

- Scripts individuais de otimização (\`set-swappiness.sh\`, \`set-swappiness-persistent.sh\`, \`set-page-cluster.sh\`, \`set-page-cluster-persistent.sh\`, \`set-zswap-enabled.sh\`) foram excluídos.
- Foi criado um script unificado e autossuficiente \`optimize.sh\` na raiz do projeto.
- A pasta \`scripts/\` foi removida e todos os scripts restantes foram movidos para a raiz do repositório.
- O script \`toggle-passwordless-sudo.sh\` e o \`README.md\` foram devidamente atualizados para refletir o novo formato unificado.
- A validação confirmou que \`optimize.sh\` aplica as configurações perfeitamente tanto de forma invisível via \`passwordless sudo\` quanto via \`PTY\` fallback caso executado em background sem a regra configurada.
- O erro de boot causado por timeout no script do memory guard foi corrigido expandindo o \`TimeoutStartSec\` para \`120s\` na unidade systemd para acomodar carga alta de leitura de logs de disco na inicialização.

## Autoresearch (Iteration 13)
Date: $(date +%Y-%m-%d)

- Foi executada uma sessão de Autoresearch para minimizar o \`memory_pressure\` (medido em delta total de microssegundos) sob uma carga de 1024 MiB por 15 segundos.
- Baseline: 53.446 (swappiness=89, page-cluster=2).
- Teste swappiness=110 piorou (111.022).
- Teste swappiness=80 melhorou muito (9.189).
- Teste swappiness=40 "zerou" (330), mas foi descartado por contornar a mecânica de swap de forma artificial (gaming the benchmark).
- Teste page-cluster=0 piorou severamente (79.176).
- Teste page-cluster=3 melhorou a baseline (4.088).
- Teste page-cluster=4 piorou o desempenho (124.901).
- Teste combinado swappiness=80 e page-cluster=3 resultou na melhor marca final sem gaming: 1.916.
- A configuração otimizada final (swappiness=80, page-cluster=3, zswap=0) foi definida como padrão no \`optimize.sh\`.

## Memory Guard entrypoint refactor
Date: 2026-08-22

Change applied:
- Renamed `early-oom/setup-memory-guard.sh` to `early-oom/memory-guard.sh`.
- The renamed entrypoint owns ZRAM, EarlyOOM and freeze evidence only. It no longer writes `sysctl` values or runs `sysctl --system`; `optimize.sh` remains the single owner of persistent kernel and zswap tuning.
- Removed `fix_earlyoom.py`; its intended thresholds and child-process matching are declared directly by `memory-guard.sh`.
- Added `early-oom/memory-guard.sh` to the `tuning` sudo profile and made its self-elevation preserve `--logging-only` and other arguments.
- Increased `memory-guard-session-log.service` startup timeout to `120s`, which covers slow `journalctl` reads on the HDD.

Validation:
- `bash -n early-oom/memory-guard.sh`, `dash -n optimize.sh`, `dash -n toggle-passwordless-sudo.sh`, and `python3 -m json.tool .context/prd_ralph/prd.json` passed.
- `bash early-oom/memory-guard.sh --help` reported the renamed entrypoint and both supported modes.
- `bash memory-guard.sh --dry-run --logging-only` completed without host writes.
- The legacy gate `dash -n scripts/zram-monitor.sh` still fails because that path is absent. This is existing monitor-path divergence, tracked by `US-004`, not caused by the Memory Guard refactor.

## Autoresearch, independent kernel tuning
Date: 2026-08-23

Scope and decision:
- O usuário manteve `vm.swappiness=80` e `vm.page-cluster=3` como a configuração já estabelecida. As medições de uma retentativa com `swappiness=89` foram sinalizadas como não comparáveis, não substituíram essa decisão e o valor foi restaurado para `80`.

Evidence:
- O baseline da configuração preservada, na execução dinâmica de 30 segundos com memória disponível mais 500 MiB, foi `5,078,455` microssegundos de `memory_pressure`.
- Aumentar `vm.min_free_kbytes` de `67584` para `98304` foi confirmado em três medições: `791,979`, `668,894` e `554,369` microssegundos. A mediana, `668,894`, reduziu o valor em 86,8% contra o baseline.
- `vm.watermark_scale_factor=20` registrou `703,936` microssegundos, pior que a mediana vencedora; o valor `10` foi restaurado.
- Uma primeira execução do baseline excedeu o timeout sem emitir métrica. A repetição concluiu em 41,3 segundos e foi usada como baseline.

Final configuration:
- `vm.swappiness=80`
- `vm.page-cluster=3`
- `vm.min_free_kbytes=98304`
- `vm.watermark_scale_factor=10`
- `zswap=0`

Validation:
- `dash -n optimize.sh` passou.
- A leitura runtime confirmou os quatro valores finais via `sysctl`.

## Browser and video acceleration
Date: 2026-08-23

Observed:
- `vainfo` 2.22.0 validated the Intel iHD VA-API driver 25.3.0 with H.264, HEVC and VP9 decode support.
- The root ext4 mount already uses `noatime`; the HDD scheduler is already `bfq`.
- `thermald`, Bluetooth, Avahi and CUPS are active. Bluetooth remains enabled at the user's direction; Avahi and CUPS remain untouched because printer discovery may depend on them.

Applied:
- The active LibreWolf profile uses the balanced 4 GiB setting: VA-API and hardware video decoding enabled, AV1 disabled, and three content processes.
- These browser preferences require a normal LibreWolf restart to become active.

## LibreWolf graphics rollback
Date: 2026-08-23

- The black screen occurred with QTerminal, tmux and Oh My Pi processes while LibreWolf was not running. The added LibreWolf preferences therefore could not have been active or causal.
- The last pre-freeze snapshot at `10:38:10` had 1,934 MiB available memory, 1,520 MiB free ZRAM, and zero PSI. It does not support memory thrashing or an EarlyOOM kill as the immediate trigger.
- The preserved logs show EarlyOOM killing Codex and Node processes earlier in that session under real pressure. They do not establish a cause for the later black screen.
- The kernel journal has no `i915`, DRM, or GPU-hang event. It does contain high-volume, pre-existing correctable `r8169` PCIe errors; these are a separate lead, not a proven cause.
- The user reconfirmed the balanced browser profile after reviewing the evidence. VA-API, hardware video decoding, AV1 disabled and three content processes are active in the LibreWolf override file; they take effect after a normal browser restart.
