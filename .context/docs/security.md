# Security notes

## Privilege model
The repository's runtime and remediation flow operate on host level resources. Changing ZRAM configuration, loading kernel modules, writing service files, and writing logs under `/var/log` all require elevated privileges on the target Lubuntu machine.

## Sensitive data handling
- `GITHUB_TOKEN.txt` is present in the repository root. Treat it as sensitive material and exclude it from normal feature work unless the task is explicitly about credential hygiene.
- Monitor logs can reveal host behavior patterns, including memory pressure windows and swap usage. They are not secrets in the same class as tokens, but they should still be readable only by intended local users.

## Current security risks
- Deployment assets referenced by the README are not versioned. Manual host drift is therefore possible.
- The monitor writes directly to fixed log paths. If permissions or ownership are wrong, monitoring silently degrades into failed writes.
- Duplicate copies of the monitor script increase the chance of patching one path while the installed path still uses another.
- Passwordless sudo, especially with the `full` profile from `toggle-passwordless-sudo.sh`, removes the normal confirmation boundary before root actions.
- The `tuning` profile now allows the swappiness helpers with any numeric value that the scripts accept, so those scripts become the last enforcement point for the `0..200` range.

## Recommended controls for future stories
- Version `systemd` and `logrotate` assets in the repository.
- Add an installation path that sets explicit owner and mode bits.
- Add a validation command that fails fast when required binaries or paths are missing.
- Prefer the `tuning` profile from `toggle-passwordless-sudo.sh` over `full` unless unrestricted root access is explicitly required.
- Keep the helper-side input validation narrow and explicit whenever the sudoers entry allows argument freedom.
- Keep secrets outside this repository and remove token files from runtime adjacent directories when possible.

## Out of scope today
This repository does not implement network services, authentication systems, or multi user access control. Its main security concern is privileged local system modification and the safe handling of local operational artifacts.

## Related resources
- [Architecture notes](./architecture.md)
- [Testing strategy](./testing-strategy.md)
- [GSD project plan](./planning_gsd/PROJECT.md)
