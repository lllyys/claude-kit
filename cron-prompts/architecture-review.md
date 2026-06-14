SCOPE: periodic strategic codebase review only. This is the OPT-IN strategic layer from `.claude/rules/60-ai-governance.md` §11 — NOT one of the four `/cron-bootstrap` jobs, and NOT a gate. It diagnoses and FILES a plan; it never implements. Suggested cadence: quarterly, or after a major architectural phase / a substantial jump in module or dependency count.

Do exactly this, then STOP:

1. **Run the review with a fixed, non-interactive preset** so it is deterministic enough to run unattended. Use `/grill:roast` against the repo root — or any equivalent whole-codebase architectural interrogator — with a fixed selection: architecture + error-handling + security + testing agents, Hard-Nosed Critique style, no interactive style/add-on prompts. (To make the review itself cross-model, run grill's Codex form `$grill-roast` instead.) If `grill` or an equivalent is not installed, record that and STOP — do not fake a review.

2. **Write the diagnostic** to `dev-docs/architecture-reviews/<YYYYMMDD>-<scope>.md`, led with metadata: reviewed commit SHA (`git rev-parse HEAD`), scope, tool + model, date, and the prior report it supersedes (if any). This is a diagnostic artifact, kept separate from `dev-docs/plans/` (governed work) and `dev-docs/spikes/` (Phase-0 probes).

3. **Triage every finding against live code** — the report is fallible (expect several findings per run to be already-done or mis-scoped). For each finding: accept / reject / defer, recording the decision and the evidence you checked. Discard the rest.

4. **File a governed plan** for the accepted findings in `dev-docs/plans/<YYYYMMDD>-architecture-<scope>.md`, WI-linked per rule 60 §1-2. Do NOT copy the report's own "fixing plan" verbatim — that skips the triage. The plan still owes an independent Codex review (rule 60 §6) before Phase 1.

5. **STOP.** Do not implement, do not open a PR. The six gates (rule 47) execute the plan later, per-change. Report the review path and the plan path you filed, then end the session.
