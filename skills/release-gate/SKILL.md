---
name: release-gate
description: Run the project's release gates and summarize results. Use when asked to run full quality gates (lint/test/build), verify readiness, or produce a gate report.
---

# Release Gate

## Overview
Run the project's full quality gate — lint -> tests (with coverage) -> build — and
summarize outcomes. The gate runs whatever this project configures: test and
coverage commands come from `.claude/tdd-guardian/config.json` (`testCommand`,
`coverageCommand`); lint and build are the project's own commands.

## Workflow
1) Confirm current branch and dirty state (`git status -sb`).
2) Run the full gate. Prefer the project's single build/gate command if it has
   one (e.g. an `all`/`check` task that chains lint -> test -> build). Otherwise
   run the steps in order:
   - the project's lint command
   - the coverage command from `.claude/tdd-guardian/config.json` →
     `coverageCommand` (or `testCommand` if no separate coverage command)
   - the project's build command
   - `scripts/run_release_gate.sh` reads the config and runs these for you.
3) If failures occur, capture the first error block and stop.
4) Report:
   - Which steps ran (lint / test+coverage / build)
   - Pass/fail status
   - Key errors and next actions

## Notes
- Prefer the full gate over partial commands unless asked.
- Do not run interactive dev servers.
