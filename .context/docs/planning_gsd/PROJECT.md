# GSD project plan

## Project
lubuntu_optimize

## Mission
Turn the current README, monitor stack, and integrated tmux/QTerminal session scripts into a reproducible, low-overhead operations kit for this Lubuntu notebook.

## Current execution pointer
- Active milestone: `M2. Version deployment assets`
- Named next Ralph story: `US-002`
- Workflow phase: `E`, execution ready
- The user-directed `US-005` consolidation of desktop session scripts completed before the queued monitor stories.
- Block rule: if `.context/docs/planning_gsd/PROJECT.md`, `.context/docs/planning_gsd/STATE.md`, `.context/prd_ralph/README.md`, `.context/prd_ralph/prd.json`, or `.context/workflow/status.yaml` is missing, execution is blocked and no story may be guessed.

## Planning assumptions
- The repository is maintained for a single low resource laptop profile first, then generalized only when needed.
- Shell plus native system tools are preferred over heavier runtime components.
- Reproducibility matters more than feature breadth.
- Every execution cycle must select one Ralph story only.

## Milestones
| Milestone | Goal | Depends on | Exit condition |
| --- | --- | --- | --- |
| M1. Planning baseline | Establish official context, PRD, and workflow files | None | Canonical planning files exist, workflow is initialized, and one named next story is available |
| M2. Version deployment assets | Store service, timer, and logrotate assets in repo with install instructions | M1 | A maintainer can install the monitoring stack from repository files instead of README prose alone |
| M3. Add validation harness | Provide repeatable non root validation for monitor logic and configuration checks | M2 | Maintainer can run a documented validation command before touching host paths |
| M4. Consolidate runtime paths | Remove duplicate monitor script drift and align README with final canonical layout | M2, M3 | Only one authoritative monitor script path remains and docs match it |
| M5. Integrate session tooling | Consolidate the tmux, QTerminal and Oh My Pi PTY scripts | M1 | Every runtime script and required local asset has one documented target path and passes its integration checks |

## Dependency map
- M2 needs M1 because deployment work should not start before tracked context, PRD, and workflow state exist.
- M3 needs M2 because validation should target the versioned deployment assets, not undocumented host state.
- M4 depends on M2 and M3 because path consolidation should happen after deploy and validation conventions are explicit.
- M5 depends on M1 because the session scripts are user-level tools with self-contained validation. It was completed by explicit user request before the queued monitor work.

## Out of scope for this plan
- GUI tools, dashboards, or background daemons.
- Network services or remote telemetry.
- Applying host changes without explicit maintainer invocation.
- Refactoring `create_and_push_repo.sh` unless a later cycle explicitly targets repository publishing.

## Success measures
- A new session can identify the active milestone and next story from `.context` alone.
- The repository versions every host artifact that the README asks the maintainer to install.
- Validation commands exist for both planning artifacts and runtime scripts.
- Only one canonical monitor script path remains after consolidation.
