# 60 - AI Governance

Rules for keeping AI-assisted implementation honest across long-running
multi-phase work. Background and field practices: see
`dev-docs/grills/ai-governance-2026-05.md`.

## 1. Plan files are the contract

Long-running features (>1 day, >5 files) must have a plan in
`dev-docs/plans/YYYYMMDD-name.md`. Plans contain ADRs, work items
(`WI-N.M`), and a Definition of Done per phase. Implementation references
the plan; the plan does not chase implementation.

## 2. Work items must be linked

Every WI in a "complete" phase must be traceable in **either** a commit
message **or** a top-of-file comment in its test file:

| Linkage path | Format |
|---|---|
| Commit message | `feat(scope): <change> (WI-1.2)` |
| Test header | `// WI-1.2 — <one-line description>` |

Verify with: `bash scripts/check-wi-linkage.sh <plan-file> [--phase=N]`.

## 3. Phase boundaries are gated by scripts, not prose

Each plan phase has machine-checkable Definition of Done. A per-plan
phase-gate script (`bash scripts/check-<plan>-phase.sh <phase-number>`)
must exit 0 before the plan's Status header ticks to the next phase.

When you start a new long-running plan, copy an existing phase-gate
script as a template and fill in per-phase assertions.

## 4. New dependencies are reviewed for hallucination

LLMs hallucinate package names at 5-22% rate (USENIX 2025), with active
slopsquatting attacks. Every PR that adds a dependency runs
`scripts/check-new-deps.sh` in CI, querying whatever registry the project's
package manager uses (npm, PyPI, crates.io, Go modules, etc.). The script
flags packages that:
- Don't exist on the registry (not found)
- Were created less than 30 days ago
- Have negligible download/usage counts

A flagged package isn't necessarily wrong, but it requires explicit
acknowledgment in the PR description before merge.

## 5. Test-first is hook-enforced for high-risk paths

For the high-risk paths, a Claude Code PreToolUse hook (provided by claude-kit)
blocks `Write`/`Edit` on production source files unless a sibling test file
(matching the project's test-file naming convention) exists. This is
structural enforcement of `.claude/rules/10-tdd.md`, not a replacement for
it.

Scope this to the project's high-risk paths — fill in the placeholders for
your codebase, e.g. an external-boundary/integration layer, core domain
logic, and shared mutable state:

```
// PLACEHOLDER — configure your high-risk paths, e.g.:
//   src/integrations/**   (third-party API/SDK layer)
//   src/core/**           (core domain logic)
//   src/state/**          (shared mutable state)
[]
```

Allow-list within scope: the project's test-file patterns plus
non-executable files (type-only declarations, style/asset files).

To extend the scope to a new feature path, edit the `SCOPED` array in the
TDD-guard hook (provided by claude-kit) (rename or add a parallel hook for
larger features).

## 6. Cross-model review at risk points

Use `/cc-suite:review-plan` against any plan exceeding ~500 lines or
spanning >3 phases before starting Phase 1. Codex (different training data,
different blind spots) catches package-name hallucinations and API
assumptions that a single-model review will miss. This is mandatory for
plans that introduce new external dependencies.

## 7. Spike before commit on high-risk technology choices

When a plan ADR rests on an unverified assumption about an external library
or a third-party API's response/protocol shape, a Phase 0 spike (under
`dev-docs/grills/<feature>/`) must validate the assumption with a runnable
probe before any other phase commits. A Phase 0 of small, runnable spikes
that each PASS before any feature WI starts is the template.

## 8. Subagent context isolation

Every frontier model degrades from ~300k tokens (Chroma 2025), well below
the 1M ceiling. For verbose tasks (search, audit, research), dispatch a
subagent rather than letting the main thread accumulate context. Use:

| Task class | Subagent |
|---|---|
| Open-ended search across the codebase | `Explore` |
| Multi-source web research | `coding-researcher` |
| Independent plan/code review | `cc-suite:review-plan`, `auditor` |
| Implementation of a single scoped WI | `execution-agent` or `implementer` |

Aggressive `/clear` between unrelated tasks; new session per phase.

## 9. Don't bypass; ask

If a hook or gate blocks legitimate work, fix the gate rather than skip
it. `--no-verify` on `git commit`, disabling the hook in the plugin's
`hooks/hooks.json`, or changing the WI-linkage script's regex are all
forbidden without explicit user authorization. Document the bypass reason
if granted.

## 10. Version bump is a single-file, last-commit step

The project versions in **one place** — its authoritative manifest/version
file (whatever the stack uses). The version bump is the last commit before
opening a PR; it does not touch any other manifest. The mechanics live in
`.claude/rules/40-version-bump.md` (this rule does not duplicate them). The
governance point: an AI agent must not invent a parallel version-bump across
multiple files when the stack has a single authoritative version source.
