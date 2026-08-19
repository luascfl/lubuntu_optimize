# Development workflow

## Current operating model
This repository now uses `README.md`, `.context/docs/`, `.context/docs/planning_gsd/`, `.context/prd_ralph/`, and `.context/workflow/` as the active planning surface. Legacy planning files outside those paths are not part of the current loop.

## Required execution loop
1. Read the canonical context files before choosing work.
2. Confirm the active milestone in `.context/docs/planning_gsd/STATE.md`.
3. Select exactly one Ralph story for the cycle.
4. Implement only that story.
5. Run the story specific validation commands and capture evidence.
6. Update `README.md` and the context docs if behavior or operating instructions changed.
7. Record the new state in `.context/docs/planning_gsd/STATE.md`.

## Repository specific conventions
- Treat `scripts/zram-monitor.sh` as the canonical runtime script path unless a later story consolidates files differently.
- Avoid introducing heavier runtime components for a low memory notebook when shell plus system utilities are sufficient.
- Keep deployment assets versioned in the repository instead of leaving them only in prose.
- Prefer explicit install and validation commands over implicit host assumptions.

## Validation expectations
Every story should end with observable evidence. The current baseline validation set is:
- `dash -n scripts/zram-monitor.sh`
- `dash -n zram-monitor.sh`
- `python3 -m json.tool .context/prd_ralph/prd.json`

Story specific validation should add more checks when new deployment assets or scripts are introduced.

## Change management notes
- The current workspace is not a Git repository, so normal commit based closeout is unavailable until the repo is initialized or recloned with `.git` present.
- The repository contains a `GITHUB_TOKEN.txt` file. Treat that as sensitive material and keep it outside normal change scope unless the user explicitly asks to manage it.
- The large `create_and_push_repo.sh` utility is not part of the ZRAM runtime path. Changes to it should happen only when the cycle explicitly targets repository publishing workflow.

## Related resources
- [Project overview](./project-overview.md)
- [Testing strategy](./testing-strategy.md)
- [GSD current state](./planning_gsd/STATE.md)
