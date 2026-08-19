# Ralph PRD

This directory contains the active Ralph PRD for `lubuntu_optimize`.

## Bootstrap note
The repository did not contain a prior PRD. This PRD was bootstrapped from the observed repository state, mainly `README.md`, `scripts/zram-monitor.sh`, `zram-monitor.sh`, and the absence of versioned deployment assets.

## Active file
- `prd.json`, canonical Ralph input for story selection and execution

## Execution preflight
Before any Ralph execution, confirm these canonical files exist:
- `.context/docs/planning_gsd/PROJECT.md`
- `.context/docs/planning_gsd/STATE.md`
- `.context/prd_ralph/README.md`
- `.context/prd_ralph/prd.json`

If any are missing, execution is blocked and story selection must not be guessed.

## Execution command
Run Ralph against this file with:

```bash
ralph build 1 --prd .context/prd_ralph/prd.json --no-commit
```

## Planning rule
Only one story should be active per cycle. The current recommended next implementation story is `US-002` after bootstrap validation completes.
