---
name: fix-issue
description: "End-to-end GitHub issue resolver — fetch, classify, branch, fix with TDD, Codex audit loop, test gate, docs-sync, version bump, PR, and post-merge close-gate finalizer. Use this skill whenever the user wants to fix a bug from a GH issue, asks 'fix issue #N', 'fix bug 115', 'work on issues #123 #456 #789', 'resolve this GH bug', or pastes a GH issue URL/number for resolution. Also handles `question`-labeled issues (inline answer + comment, no branch). REDIRECTS feature/enhancement issues to feature-workflow per rule 47. Supports both single-issue and multi-issue (worktree) pipelines."
---

# Fix Issue

Resolve one or more GitHub issues end-to-end: fetch, classify, branch, fix with
TDD, Codex audit loop, test gate, docs-sync, version bump, PR, and post-merge
close-gate finalizer.

## Input

Parse the user's request to extract one or more issue numbers (e.g. `#123`, `123`, `#123 #456`). If no numbers were provided, print usage and STOP.

## Scope

| Issue type | Path inside this skill |
|---|---|
| Bug (label `bug` or body describes broken behavior) | Single-issue **Bug Pipeline** below |
| Question (label `question`) | Inline answer + comment, no branch/PR |
| Feature / enhancement | **REDIRECT** to `/feature-workflow` (see "Feature handling" below) |
| Multiple issues at once | **Multi-Issue Pipeline** (one worktree per issue) |

### Feature handling — read this before fixing a feature here

`.claude/rules/47-feature-workflow.md` is **binding for every feature
implementation**: Plan → Independent plan audit → TDD → Implementation
audit → Integration verification → Merge. Six gates, never skip
one. This skill cannot run Gate 2 (independent plan audit by a separate
agent context) or Gate 5 (integration verification + evidence
file) inline. Therefore:

**Always redirect features to `/feature-workflow`. STOP this pipeline.**
No user waiver bypasses Gates 2 or 5 — rule 47 is binding for every
feature regardless of size. The old escape hatch (10+ files / 4+ work
items) is gone; the previous "opt out in writing" is gone too.

The skill's old `3b. Feature Path` is removed. Feature handling lives
entirely in `/feature-workflow`.

## Hooks you'll trip

Three PreToolUse hooks (provided by claude-kit, wired via the plugin's
`hooks/hooks.json`) gate this pipeline:

| Hook | Triggers when | What it requires |
|---|---|---|
| `check_codex_audit_artifact.sh` | `gh pr merge` on a source-touching PR | `.claude/codex-audits/<branch>-audit.md` with valid `final_verdict` |
| `check_gh_issue_mirror.sh` | `Edit/Write/MultiEdit` on `docs/{features,bugs}.md` | mirror-required rows must have `GH: #N` in Notes column |
| `check_terminal_status_evidence.sh` | tracker flip to `VERIFIED` (features) or `FIXED` only on `docs/features.md` | matching `dev-docs/verification/<kind>-<id>-<YYYYMMDD>.md`. **Bug `FIXED` flips on `docs/bugs.md` are NOT hook-enforced** — verification is enforced at GH-issue-close time, not at row flip. |

Plan around them; do not bypass.

## Pre-flight Checks

1. **Parse arguments** — extract issue numbers (e.g. `#123`, `123`, `#123 #456`).
   - No arguments: print usage and STOP.
2. **Check working tree** — `git status --porcelain`. If dirty, do not
   revert unrelated changes; isolate your work with a new branch.
3. **Confirm branch / sync** — `git branch --show-current` and
   `git fetch origin`.

---

# Single-Issue Bug Pipeline

When exactly one issue is provided and it classifies as a bug, run
phases 1-9 sequentially.

### Phase 0.5: Reproduce (recommended)

Reproduce the bug before diving into code — by running the app for
behavioral bugs, or as a failing test for logic bugs:
- **UI / behavioral bugs**: run the app the way this project runs it
  (CLI, server, desktop, browser, or a test harness) and reproduce the
  symptom; automate the repro with the project's E2E tool when possible.
  Watch logs / console / output for errors.
- **Logic / state / integration bugs**: write a failing test (using the
  project's test framework) that captures the broken behavior (this
  becomes the Phase 3 RED test).
- Capture evidence — screenshots, traces, logs, or the failing test
  output.

### Phase 1: Fetch & Classify

```bash
gh issue view {N} --json number,title,body,labels,state,assignees
```

- If issue not found or closed: warn user, ask whether to proceed, or STOP.
- Classify:

| Classification | Trigger | Path |
|---|---|---|
| Bug | label contains `bug`, or body mentions error/crash/broken | continue this pipeline |
| Feature | label contains `feature`/`enhancement` | **redirect to `/feature-workflow`** and STOP |
| Question | label contains `question` | jump to **Question Path** below |
| Ambiguous | no matching labels | ask user to classify |

### Phase 2: Branch Setup

- Slug from title: lowercase, strip non-ASCII, replace spaces with `-`,
  truncate to 40 chars.
- Branch name: `fix/issue-{N}-{slug}`.
- If branch already exists: ask user — reuse or rename.
- Create and checkout the branch.
- **Tracker move**: edit `docs/bugs.md` row → status `IN PROGRESS`.
  Reminder: the `check_gh_issue_mirror.sh` hook requires `GH: #N` in the
  row's Notes column. The issue you're fixing already exists, so add
  `GH: #{N}` to Notes if absent.

### Phase 3: Resolve (Bug)

No half measures. Follow the bug-fix workflow from `docs/bugs.md`:

1. **Reproduce** — read relevant code, trace call chain symptom → root cause.
2. **Diagnose** — find root cause; check for similar patterns elsewhere.
3. **RED** — failing test (using the project's test framework) capturing
   the bug per `.claude/rules/10-tdd.md`. Match the test shape to the unit:
   - Stateful module / store bug → test driving the public actions, with state reset between cases
   - I/O or integration-boundary bug → test against a mocked transport / fake dependency, no real external calls
   - UI component / view bug → test through the project's UI test harness, querying by user-facing identifiers
   - Pure utility bug → table-driven / parameterized test covering the broken case
4. **GREEN** — fix the root cause with minimal, focused changes.
5. **REFACTOR** — clean up without changing behavior; tests stay green.

### Phase 4: Codex Audit Loop (max 3 iterations)

#### 4a. Collect changed files

```bash
git diff main --name-only
git diff main
```

#### 4b. Initial audit via the configured Codex runner

Run the project's configured **independent Codex audit runner**. Current
runner: **`cc-suite`**, which drives Codex through `codex exec` (a
killable, deadline-bounded CLI runner). Do NOT use `ToolSearch +codex` or
`mcp__plugin_codex-toolkit_codex__codex` — cc-suite intentionally avoids the
MCP bridge (it hangs on long responses) and the old `codex-toolkit` MCP
server is no longer loaded.

Default to a **read-only audit** via **`/cc-suite:audit`** (Codex audits,
*you* fix — this preserves the rule-48 author/auditor separation). Point it
at the changed files (`git diff main --name-only`) and have it focus on:

1. Correctness & logic — does the fix actually solve the root cause?
2. Edge cases — boundary conditions, null/undefined, empty input, Unicode / non-ASCII text, cancellation mid-operation, concurrent state updates
3. Security — injection / unsafe rendering of untrusted input, input sanitization, no secrets (API keys, tokens) leaked to logs or any client-shipped artifact
4. Duplicate code — repeated logic that should be unified
5. Dead code — unused imports, unreachable branches, orphaned functions
6. Shortcuts & patches — workarounds, TODO markers, band-aids
7. Project conventions — language/type strictness (no escape hatches that defeat the type checker), resource cleanup, no stale references, file size <300 lines (see `.claude/rules/50-codebase-conventions.md`)
8. Boundary discipline — feature code goes through the project's designated abstraction layers rather than reaching past them into third-party SDKs directly; long-running / async operations handle cancellation and partial results

`/cc-suite:audit` reports findings as: file:line | severity | issue | fix.
(`/cc-suite:audit-fix` runs the full audit→fix→verify loop with Codex
driving the fixes — use it only if you want Codex-authored fixes and will
review them yourself; `/cc-suite:status|result|cancel` track a running job.)

#### 4c. Parse & fix

Fix **every** finding — Critical, High, Medium, Low.

#### 4d. Verify

Re-run **`/cc-suite:audit`** on the updated diff to confirm every finding is
resolved and no new issue was introduced. (If you used `/cc-suite:audit-fix`,
its built-in verify pass already covers this.)

#### 4e. Loop or exit

- Zero findings → audit passes, exit loop.
- Findings remain and iteration < 3 → fix and re-verify.
- 3 iterations with findings still open → STOP. Report remaining issues
  to the user.

#### 4f. Fallback — manual mini-audit

If the Codex runner is genuinely unavailable (the `codex` CLI is missing or
unauthenticated, or cc-suite errors): read each changed file, audit
dimensions 1–8 above, and fix Critical/High inline.

#### 4g. Write the audit log artifact

**Required before merge; recommended before PR creation so review sees
it.** `check_codex_audit_artifact.sh` blocks `gh pr merge` (not
`gh pr create`) without an audit log. Write the file before attempting
the merge so the hook passes.

Path: `.claude/codex-audits/<branch-with-slashes-replaced-by-hyphens>-audit.md`

Frontmatter (required):

```markdown
---
branch: <current branch name, exactly as `git branch --show-current` returns>
threadId: <Codex exec session id>    # OR `manual-fallback` if 4f was used
rounds: <integer ≥ 1>
final_verdict: ship-as-is | follow-up-recommended | block-recommended
date: YYYY-MM-DD
---
```

Body:
- Per-round findings (file:line | severity | issue | fix).
- Resolution note for each finding (fixed / accepted with rationale /
  deferred to follow-up bug).
- Summary verdict statement.
- If you used manual fallback, include a "Manual audit evidence" section
  per `.claude/rules/47-feature-workflow.md`'s manual-fallback rules
  (files read, symbols verified, edge cases checked, risks accepted).

Commit the audit log alongside the fix, in its own commit
(`chore: codex audit log for issue #{N}`) or folded into the relevant
fix commit — but it must be on the branch before the PR opens.

### Phase 5: Test Gate

Up to 3 attempts: run the project's build/gate command (see
`.claude/rules/40-version-bump.md` and `.claude/tdd-guardian/config.json`).
The release-gate skill runs whatever the project configures — typically
lint → tests + coverage → build chained together.

> **Note**: the project's build/gate command is the binding quality
> gate. Iterate faster during the fix by running just the affected spec
> via the project's test command (see `.claude/tdd-guardian/config.json`
> → `testCommand`), but the fix is not done until the full gate (lint +
> coverage + build) is green.

- Pass → proceed.
- Fail → read errors, fix, retry.
- 3 failures → report, keep branch, STOP.

### Phase 6: Tracker State + Docs Sync

#### 6a. Pre-FIXED verify (mandatory)

The `docs/bugs.md` workflow is **Understand → RED → GREEN → REFACTOR
→ Verify → Track**. "Verify" comes BEFORE "Track" (the FIXED flip).

Run a lightweight pre-merge confirmation that the symptom is actually
gone — not just that tests pass. This is distinct from the deep
post-merge close-gate verification in Phase 9; that one runs against
the merged build on `main`.

- **UI / behavioral bugs**: re-run the original repro from the issue
  body against the working-tree build, running the app the way this
  project runs it (CLI, server, desktop, browser, or a test harness);
  drive it with the project's E2E tool when possible. Confirm the actual
  symptom is gone.
- **State / async / integration bugs**: re-run the failing scenario
  end-to-end against the working-tree build. Confirm the broken state no
  longer reproduces.
- **Pure-logic bugs reproducible by a unit test**: the RED→GREEN
  transition in Phase 3 already establishes "Verify" — no extra step
  needed.

If pre-FIXED verify fails: the fix is incomplete. Loop back to Phase 3
(or revert) — do NOT advance to Phase 6b.

#### 6b. Bug tracker — FIXED flip

`docs/bugs.md` row → status **`FIXED`** (only after 6a verify passed).
The `check_terminal_status_evidence.sh` hook does NOT block bug
`FIXED` flips — verification is enforced at issue-close time
(Phase 9), not at this row flip. Add `GH: #{N}` to the row's Notes
column if absent (`check_gh_issue_mirror.sh` will block otherwise).

#### 6c. Docs sync (if triggered)

Per `.claude/rules/24-doc-sync.md`:

| If your fix touched | Update |
|---|---|
| New module boundary / shared abstraction / cross-feature pattern | `docs/architecture.md` |
| User-visible behavior, tech stack, requirements, setup, ≥5-row tracker change | `README.md` |
| Otherwise | nothing |

If updates are needed, commit them in their own commit
(`docs: update architecture.md for #{N} fix` etc.) **before** the
version bump in Phase 7. Pure bug fixes with no architectural impact
need nothing here.

### Phase 7: Version Bump

Per `.claude/rules/40-version-bump.md`. Mandatory tail commit before PR.
Bump the semver version wherever this project records it — its manifest
(e.g. `package.json`, `pyproject.toml`, `Cargo.toml`, a `VERSION` file,
etc.). The steps are manifest-agnostic:

```bash
# 1. Bump the version field to X.Y.Z in the project's manifest (patch for bug fixes).
# 2. Confirm the field updated (grep the manifest for the new version).
# 3. Run the project's build/gate command as a smoke check.
# 4. Commit:
git add <manifest>
git commit -m "chore: bump version to X.Y.Z"
```

For bug fixes, increment **patch**. The post-merge tag (`v X.Y.Z`) is
cut from the merge commit on `main` after PR lands.

### Phase 8: Create PR

PR uses `Refs #N`, **not** `Fixes #N` (prevents premature auto-close —
the GH issue stays open until verified, see Phase 9).

```bash
gh pr create --title "fix: {concise description}" --body "$(cat <<'EOF'
## Summary

{1-3 bullets describing what changed and why}

Refs #{N}

## What Changed

{list of key changes}

## Codex Audit

{audit summary — iterations run, findings fixed, verdict}

Audit log: `.claude/codex-audits/{branch-slug}-audit.md`

## Validation

- [x] Project build/gate command passes
- [x] Tests cover changed behavior (TDD: RED → GREEN)
- [x] Codex audit loop completed ({M} iterations, verdict: {verdict})
- [x] Docs sync — {architecture.md updated | README.md updated | n/a}
- [x] Version bumped: {old} → {new}

## Post-Merge Verification Plan

Default path (run-the-app verification): {how the original repro will be re-run against the merged build, E2E tool when possible}.
OR exception path (high-fidelity test): {test name + evidence file path}.

## Type of Change

- [x] Bug fix (Refs #{N})
EOF
)"
```

Report the PR URL to the user.

### Phase 9: Post-Merge Finalizer (close gate)

**Do NOT auto-`gh issue close`.** Per AGENTS.md "Close gate — verified,
not just merged":

#### 9a. Right after `gh pr merge`

1. Apply the appropriate label to the GH issue:
   - **Default — `awaiting-verification`**: failure can be reproduced by
     running the app. Most bugs.
   - **Exception — `verification-exception`**: failure mode physically
     cannot be reproduced by running the app (race conditions,
     fault-injection paths, cancellation/network failures, concurrent
     state transitions, etc.). Requires a deterministic high-fidelity
     integration test at real subsystem boundaries (not casual stubs)
     + evidence file in `dev-docs/verification/`.
   - **Blocked — `verification-blocked`**: neither a run-the-app repro
     nor a high-fidelity test is feasible yet (no harness exists). Keep
     open with a follow-up to build the harness (potentially as a feature).

2. Post a "shipped, awaiting verification" comment:

   ```
   gh issue comment {N} --body "Shipped in v{X.Y.Z} (commit {short-sha}). Awaiting {run-the-app verification|verification-exception evidence}."
   ```

3. Tag is cut by the version-bump tag policy from `main`:

   ```bash
   git fetch origin
   git checkout main && git pull
   git tag v{X.Y.Z}        # only if not already tagged on the merge commit
   git push origin --tags
   ```

#### 9b. Verification + closure

For the **run-the-app verification** path:
- Check out and run the merged build the way this project runs it
  (CLI, server, desktop, browser, or a test harness).
- Re-run the original repro from the issue body; drive it with the
  project's E2E tool when possible.
- Confirm the symptom is gone.
- Post closure comment with: commit SHA + what was tested + what was
  observed.

   ```
   gh issue comment {N} --body "Verified by running the merged build (commit {sha}). Re-ran the original repro: {what you did}. Observed: {what happened}. Symptom is gone."
   gh issue close {N}
   ```

For **verification-exception** path:
- Confirm a deterministic high-fidelity integration test covers the
  failure path through real subsystem objects (the relevant module
  boundaries, pipelines, and stateful components — not stubbed). Casual
  unit tests with stubs do NOT qualify.
- Write or update the evidence file at
  `dev-docs/verification/bug-{N}-{YYYYMMDD}.md` per the schema in
  `dev-docs/verification/SCHEMA.md`. Required frontmatter:

   ```yaml
   ---
   kind: bug
   id: {N}
   status_target: FIXED
   commit_sha: {40-hex of merge commit on main}
   app_version: {version from the project manifest}
   date: YYYY-MM-DD
   verifier: <name or "claude">
   environment: <how the app was exercised, e.g. "CLI on macOS 15.4", "Chromium 126 (Playwright)", "server + curl">
   os_version: <e.g. "macOS 15.4">
   build_mode: <how it was built/run, e.g. dev | preview | production | release>
   dependencies: <relevant external deps or services, e.g. "local backend", "mocked transport", or "n/a">
   result: pass | partial | fail
   ---
   ```

   Required body sections (the hook does not parse the body but rule
   47 + SCHEMA both require them):

   - `## Acceptance criteria` — table mapping each criterion to
     observed behavior + pass/fail.
   - `## Commands run` — fenced code blocks of the actual commands that
     exercised the fix (shell, test runner, E2E tool, HTTP calls).
     Reproducible recipe.
   - `## Observations` — narrative; what was surprising, what was
     close to a regression.
   - `## Artifacts` — paths to screenshots, traces, log captures.
     Optional but strongly recommended.
- Closure comment cites the test method + evidence file path:

   ```
   gh issue comment {N} --body "Verification exception: deterministic high-fidelity integration test {TestClass.testMethod} at {file:line} drives the same code path the production failure would hit. Evidence: dev-docs/verification/bug-{N}-{YYYYMMDD}.md."
   gh issue close {N}
   ```

If `verification-blocked`: do not close. Add a follow-up task to build
the missing harness and revisit when it lands.

---

# Question Path

If Phase 1 classified the issue as `question`:

1. **Research** — read code and docs to compose a thorough answer.
2. **Detect language** — check the issue author's language from title
   and body. Reply in the **same language** the author used.
3. **Respond**:

   ```bash
   gh issue comment {N} --body "{answer in author's language}"
   ```

4. **STOP** — no branch, no PR, no version bump. If you created a
   branch in Phase 2 by mistake, delete it. Question issues do not move
   through the close gate.

---

# Multi-Issue Pipeline

When multiple issue numbers are provided (e.g. `#123 #456 #789`).

### M1: Fetch & validate all

```bash
gh issue view {N} --json number,title,body,labels,state
```

- Filter out closed issues (warn user).
- Filter out questions (handle inline with `gh issue comment`, no worktree).
- Filter out features (redirect each to `/feature-workflow`).
- Remaining bugs proceed to worktree pipeline.

### M2: Create worktrees

```bash
git worktree add .claude/worktrees/issue-{N} -b fix/issue-{N}-{slug} main
```

### M3: Parallel execution

Per `.claude/rules/48-parallel-execution.md`, parallelism is an
isolation tool first, speed tool second.

Each worktree-agent runs **Phases 0.5 → 6c only**, then stops and
reports "ready for bump." The integrator (orchestrator agent or human)
controls everything from Phase 7 onward, with three coordinated gates:

1. **Version bump is integrator-coordinated.** After all worktree-agents
   stop at the end of Phase 6c, the integrator assigns sequential
   manifest versions to the bug PRs in the order they will land,
   then resumes each worktree-agent through Phases 7 → 8 (version
   bump, then PR creation) with its assigned version. This avoids two
   parallel branches picking the same next version off the same
   `main` baseline.

2. **PR merge order is sequential, not parallel.** After all worktrees
   open PRs, the integrator merges them one at a time. Each PR is
   rebased on `main` immediately before merge so it carries an
   already-bumped version that doesn't collide with what just landed.

3. **Tagging happens once, on `main`, after all merges land.** No
   worktree tags. Worktree-agents NEVER run `git tag` or
   `git push origin --tags`. The integrator tags `main` once per
   merged version after the final merge.

Phase 9 (post-merge finalizer + verification + closure) is serial:
run after all merges land in their assigned version order. Run-the-app
verification is sequential — drive one verification session at a time so
observations aren't conflated.

### M4: Collect results

```
| Issue | Status | Branch | PR | Audit verdict | Tag |
|-------|--------|--------|------|---------------|-----|
| #123  | Merged, awaiting-verification | fix/issue-123-slug | #45 | ship-as-is | v3.13.6 |
| #456  | Failed (gate) | fix/issue-456-slug | — | — | — |
```

### M5: Cleanup worktrees

```bash
# Remove successful worktrees (this also drops each worktree's
# installed dependencies / build output, so no separate cleanup is needed)
git worktree remove .claude/worktrees/issue-{N}

# Remove empty worktree directories
rm -rf .claude/worktrees/agent-*

# Keep failed worktrees for investigation
```

---

## Error Handling

| Scenario | Action |
|---|---|
| No arguments | Print usage, STOP |
| Issue not found / closed | Warn, ask user |
| Issue is a feature | Redirect to `/feature-workflow`, STOP |
| Dirty working tree | Isolate with branch, don't revert unrelated changes |
| No labels (ambiguous type) | Ask user to classify |
| Codex runner unavailable | Use 4f manual fallback; mark audit log `threadId: manual-fallback` |
| Test gate fails 3x | Report errors, keep branch, STOP |
| `check_gh_issue_mirror.sh` blocks tracker edit | Add `GH: #N` to the row's Notes column, retry |
| `check_codex_audit_artifact.sh` blocks `gh pr merge` | Verify the audit log file exists at the expected path with valid frontmatter |
| `check_terminal_status_evidence.sh` blocks tracker edit | Only fires for features (`VERIFIED`) — bug `FIXED` is not gated. If you hit it, you're flipping a feature row; write the evidence file |
| Branch already exists | Ask user: reuse or rename |
| Verification reveals a regression | Reopen the issue, file a new bug, do NOT close |
