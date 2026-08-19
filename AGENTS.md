# AGENTS.md

## Project scope
- This repository tracks Lubuntu memory pressure hardening around ZRAM alignment and the `zram-monitor.sh` monitoring flow.
- Treat `scripts/zram-monitor.sh` as the canonical runtime script path until a dedicated consolidation story changes it.
- `create_and_push_repo.sh` is out of scope unless the active story explicitly targets repository publishing.

## Canonical context
Read these files before planning or execution:
- `README.md`
- `.context/docs/README.md`
- `.context/docs/planning_gsd/PROJECT.md`
- `.context/docs/planning_gsd/STATE.md`
- `.context/prd_ralph/README.md`
- `.context/prd_ralph/prd.json`
- `.context/workflow/status.yaml`

## Story execution rules
- Select exactly one Ralph story per cycle.
- Do not guess a story if any canonical planning file is missing.
- Update `README.md` and `.context/docs/` whenever behavior, installation steps, or validation commands change.

## Validation commands
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`

## Environment notes
- This workspace currently has no `package.json`, so `npm run build`, `npm run dev`, and `npm run test` are not applicable here.
- This workspace is not a Git repository in its current filesystem state, so commit based closeout is unavailable until `.git` is restored.
