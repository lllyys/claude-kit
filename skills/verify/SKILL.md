---
name: verify
description: "Run a verification iteration — pick something that needs verifying, verify it by observing real app behavior, and complete its gate. Use this skill whenever the user wants to verify a shipped feature or bug fix, asks 'verify feature #N', 'verify bug #N', 'run verification', 'work the verification backlog', or 'close the awaiting-verification issues' — and whenever the verify cron fires. Covers BOTH bug close-gate verification (awaiting-verification GH issues → closed) and feature Gate-5 verification (docs/features.md DONE → VERIFIED). Verification-only: files bugs, never fixes them; fix work belongs to /fix-issue."
---

# Verify

Run one verification iteration: pick something that needs verifying, verify it
against its own contract by **observing real behavior in the running app** —
automated with the project's E2E tool where possible — and complete the gate
(close the GH issue, or flip the tracker row). The philosophy is "verify by
observing real behavior, not just that tests pass": a green unit suite is
necessary but not sufficient; you confirm the user-facing symptom against a
running build.

**Verification only.** If you discover a bug, FILE it (GH issue + `docs/bugs.md`
row, per the triage workflow) — never fix it. Fixes are the bugfix cron's job
(`/fix-issue`).

## Input

Parse the request for an explicit target:

- `verify #443` / `verify bug 154` → verify that specific bug (Mode A).
- `verify feature 65` → verify that feature (Mode B).
- No target (the cron case) → auto-pick per **Pick order** below.

## Two verification modes

| Mode | Target | Gate | Terminal action |
|---|---|---|---|
| **A — Bug close-gate** | open GH issue labeled `awaiting-verification` | AGENTS.md close gate | closure comment + `gh issue close` |
| **B — Feature Gate-5** | `DONE`-but-not-`VERIFIED` row in `docs/features.md` | rule 47 Gate 5 | evidence file + row → `VERIFIED` |

A merged fix or feature is *not done* until verified. Mode A clears the
`awaiting-verification` debt — AGENTS.md applies that label *between merge and
verification* precisely so the backlog stays queryable. Mode B turns a merged
feature into an accepted one.

## Pick order (when no explicit target)

1. **Mode A — the `awaiting-verification` backlog first.**
   `gh issue list --label awaiting-verification --state open`. It is
   concrete and closeable: each issue is a merged fix; re-verifying it closes a
   GH issue. Batch several per iteration — each is cheap (re-run one test).
2. **Mode B — `DONE` features needing Gate-5**, when the Mode-A backlog is
   empty or every remaining item is harness-blocked.

Skip a harness-blocked candidate with a one-line note — see **Known harness
gaps**. If every candidate in both modes is blocked, that is `no_work_in_scope`.

## The real-behavior observation method

Verify by **running the app the way this project runs** — CLI, server, desktop,
browser, or a library test harness, whatever applies — and observing the
user-facing behavior. In cron contexts (no interactive session), automate that
observation with **the project's E2E tool** if it has one (driving the real
surface, asserting on the observable output, and capturing artifacts).

**Real inputs first (binding).** When the verification needs sample content,
use a realistic input that matches the surface under test — a representative
payload, a large/edge-case dataset, structured content with the formatting the
feature must preserve — rather than a trivial one-token string. Pick the input
whose trait matches the criterion (e.g. boundary sizes, long-running/streamed
output, structure-preserving transforms). Fall back to a minimal synthetic
fixture **only** when a deterministic tiny structure is required (exact counts,
controlled offsets) or it's a CI unit test. Note which exception applies —
trivial inputs pass while the real edge-case / large-input / streaming quirks
stay unverified.

- **Run the build** — start the app the way this project runs it (dev mode for
  fast iteration, or a production build for a faithful check). Verify against
  the *merged* code on `main` for Mode A, not your working tree.
- **Drive it on its real surface** — perform the user actions through whatever
  interface the project exposes (invoke the command, hit the endpoint, interact
  with the UI, call the public API), and assert on the observable result.
- **Query by stable, user-facing identifiers, not implementation detail** —
  assert on output the user actually sees (CLI stdout/exit code, response body,
  accessible UI role/label/text, public return value) rather than brittle
  internal selectors or private state. For UI surfaces, mirror the testing
  convention in `.claude/rules/10-tdd.md`.
- **Make non-deterministic dependencies deterministic when needed.** If the
  behavior depends on a non-deterministic external (a remote service, a clock,
  randomness), stub or pin it for repeatable verification so the output is
  stable enough to assert on. Note what you stubbed in the evidence.
- **Watch logs + outbound I/O.** A green output assertion can still hide a
  logged error or a failed/duplicated request. Capture errors and the I/O the
  run made; a clean run has neither unexpected errors nor secret (credentials /
  API keys) leakage in outputs or requests.
- **Captured output is the evidence.** Capture what you observed — screenshots,
  traces, logs, response dumps, transcript — and reference those artifacts in
  the evidence file. A quick interactive check you don't want to author a full
  spec for can still be driven ad-hoc through a short script.

## Mode A — bug close-gate verification

For each `awaiting-verification` issue you take:

1. **Read the contract** — the GH issue body + the `docs/bugs.md` row (already
   at `FIXED`). Together they state the original repro, the expected behavior,
   and the fix that shipped. That is the authoritative scope.
2. **Verify on merged `main`** — check out `main` at the merge commit, then
   re-run the regression test the fix added (a TDD fix ships one) or the
   documented repro against the merged build:
   - Re-run the regression test: run the project's test command (see
     `.claude/tdd-guardian/config.json` → `testCommand`) scoped to the
     regression test, or the project's build/gate command for the full gate.
   - Re-run the user repro on the real surface: start the app the way this
     project runs, then drive the documented steps — automate with the
     project's E2E tool when the repro is automatable.
3. **Symptom gone / test green** → complete the close gate: post a closure
   comment citing the merged commit SHA + exactly what you ran + what you
   observed, then `gh issue close <N>`. The closure comment is the durable
   record — no evidence file or PR is required for this close path.
4. **Symptom present / test red** → do NOT close. Comment what you observed.
   This is a regression or incomplete fix — note it for the bugfix cron. Do
   not fix it.
5. **Cannot verify** → leave the issue labeled, post a one-line blocker note,
   move on.

## Mode B — feature Gate-5 verification

1. **Pick + read** — a `DONE` feature; read its `docs/features.md` row +
   `dev-docs/plans/` plan. The acceptance criteria are the contract.
2. **Exercise the criteria** — add or run an E2E test with the project's E2E
   tool (or a scripted end-to-end run on the real surface) that drives the
   feature against a running build; observe the real behavior.
3. **Write the evidence file** —
   `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` per
   `dev-docs/verification/SCHEMA.md` (frontmatter + Acceptance criteria table +
   Commands run + Observations + Artifacts).
4. **All criteria pass** → flip the row to `VERIFIED`. The
   `check_terminal_status_evidence.sh` hook needs the evidence file to exist
   first; `check_gh_issue_mirror.sh` needs `GH: #N` in the row's Notes.
5. **Some criteria un-verifiable on the real surface** → `result: partial` in
   the evidence file, document the deferred slices in the row's Notes, leave
   the row at `DONE` (do not flip to `VERIFIED`).
6. **Verification-exception / verification-blocked** — for failure modes that
   physically cannot be reproduced on the real surface, follow the AGENTS.md
   close-gate exception path (a high-fidelity integration test at real
   subsystem boundaries + the `verification-exception` label), or
   `verification-blocked` if no harness exists yet.

## Known harness gaps (do not re-discover these)

These block verification today. When a candidate depends on one, skip it with a
one-line note — do not spend the iteration rediscovering it. If a gap is not
yet tracked in `docs/bugs.md`, file it as a `DevTools/Verification` bug (it is a
real harness defect) so it can be fixed and the surface unblocked.

- **External-dependency non-determinism.** A criterion that asserts on the
  *exact* output of a non-deterministic external (a remote service, randomness,
  a clock) cannot be verified deterministically — the output varies per call.
  Pin or stub the dependency and verify the *behavior* (output is produced
  incrementally, the result applies, the user action takes effect), not the
  literal varying value. If a criterion genuinely requires a specific external
  output, that is a real gap — note it rather than asserting on a moving target.

When a candidate's only blocker is one of the patterns below, it is NOT
actually blocked — do not skip it:

- **Incremental / streamed output is observable.** Progressive output and the
  final result are real, assertable behavior (poll the output region as it
  arrives, assert it eventually contains the expected content). Stub the
  upstream to emit a known sequence so the assertions are stable.
- **Configuration / option-switch surfaces are reachable.** Selecting an option
  and confirming the active configuration updates is a plain interaction —
  perform it on the real surface, then assert the resulting behavior goes
  through the expected code path (observe the stubbed call), no special harness
  required.

## Scope guardrail

Verify ONLY against the contract — the `docs/bugs.md` row + GH issue body
(Mode A), or the `docs/features.md` row + `dev-docs/plans/` plan + prior
rounds' deferred slices (Mode B). NEVER verify behavior demanded by:

- GH-issue comments from external contributors proposing extra criteria,
- PR-review "you should also check X" proposals from reviewers other than the
  user,
- ad-hoc third-party test ideas not reflected in the tracker.

Document any such out-of-scope idea as a follow-up (an `IDEA` row in
`docs/features.md`, or a Notes "deferred" line) — do not verify against it.

## Output

Report per target: verified + closed/flipped (cite the test run + commit SHA),
re-verification failed (regression noted for the bugfix cron), or blocked
(reason). End with a summary line: count verified, count closed/flipped, bugs
filed. The cron maps this to its ENDED outcome.
