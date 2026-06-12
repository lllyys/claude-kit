# 48 — Parallel Execution

## Purpose

Parallelism is an **isolation tool first and a speed tool second**. Use it when it reduces wall-clock time without weakening review, audit, TDD order, or resource ownership. Use it wrong and you trade serial work for merge hell, audit gaps, or flaky shared-resource runs.

This rule applies to: spawning subagents, launching parallel `/fix-issue` runs, splitting work across git worktrees, or running concurrent feature implementations.

## Decision test

Before parallelizing, estimate honestly:

```
expected wall-clock saved  >  setup + review + conflict + resource-contention + failure cost
```

| Cost | What it covers |
|---|---|
| **setup** | Worktree creation, branch hygiene, subagent brief writing, dependency-install warmup |
| **review** | Main-agent integration time when subagent returns |
| **conflict** | Shared file edits (the manifest/version file, `docs/features.md`, `docs/architecture.md`) → rebase |
| **resource** | One E2E/browser instance, one Codex/test session at a time |
| **failure** | Probability the subagent drifts and needs collapse + redo |

If the answer isn't clearly positive, don't parallelize.

## Hard rules (non-negotiable)

1. **Author/auditor separation**: the agent that writes a plan, code, or PR is never the agent that audits it. (cc-suite running Codex as a separate `codex exec` process satisfies this by accident; preserve the boundary explicitly.)
2. **Hard dependency blocks downstream Gate 3**: if feature B depends on feature A, you cannot start B's TDD until A is `DONE`. Dependency graph in the tracker is the source of truth.
3. **One writer per file/area at a time**: two agents can work the same feature if their write sets are disjoint and explicit. Two agents writing the same file is a merge conflict you will lose.

## Strong defaults (negotiable with cause)

- Shared-file edits (status flips, version bumps, doc-sync) require **one owner** or a **final integration pass**. They batch at PR merge time, not in parallel.
- Planning subagents are **read-only by default** — return content/patch for the main agent to apply. Write access only when the subagent has its own worktree.
- Parallel verification runs that share a stateful resource (an E2E/browser instance, a dev server port, a database, a fixture directory) require **explicit instance ownership** (separate ports/profiles/fixtures). Otherwise contention produces misleading test failures.

## Subagent contract (every spawn must specify)

| Field | Required content |
|---|---|
| **Objective** | One sentence — what deliverable you want |
| **Inputs** | Exact file paths to read; relevant audit-gap context (don't rely on "absorbing" parent conversation) |
| **Allowed writes** | Either "none" (read-only, return content) or a specific path prefix |
| **Forbidden actions** | What it must NOT do (e.g., "no production code", "no running the project's build command", "no PR") |
| **Output format** | What the return message must contain |
| **Stop condition** | When to return — explicit completion criteria |

A subagent without one of these will drift.

## Subagent failure handling

- Subagent output is **advisory until reviewed** by the main agent.
- If it drifts, **re-brief once** with a narrower task. Don't ask it to self-correct indefinitely.
- If still bad, **collapse to the main agent**. Discard the subagent's output.
- **Never merge or apply** generated code/plan text without main-agent review.

## Decision matrix (gate-by-gate)

| Two work units' state | Approach |
|---|---|
| Both Gate 1 (planning) | Single agent, sequential — context switch is cheap |
| Mixed Gate 1 (planning) + Gate 3 (TDD) | Inline Gate 3 + read-only subagent for Gate 1 (tight brief) |
| Both Gate 2 (plan audit) | Parallel OK — independent Codex sessions, different threads |
| Same feature, Gate 2 of plan + Gate 3 of WI on same plan | **Serialize** — never implement against an unaudited plan |
| Both Gate 3 (TDD) on disjoint files | Worktrees + one agent each |
| Both Gate 3 (TDD) on overlapping files | **Serialize** — one writer per area |
| Same feature, WI-N-1 Gate 5 + WI-N Gate 3 | Parallel only if WI-N doesn't depend on WI-N-1's verification result |
| Both Gate 4 (impl audit) | Parallel OK — independent audits |
| Both Gate 5 (verification) | **Serialize** unless each run owns a distinct stateful resource instance (separate port/profile/fixture) |
| Mixed Gate 5 + Gate 3 | Parallel OK — different resources |

## Worktree rules

- Use a worktree when **isolation prevents more cost than it adds**. A 30-min high-risk schema change can deserve one; a 4-hour docs-only plan rarely does.
- Worktrees go under `.claude/worktrees/<feature-or-issue-id>/`.
- After removing a worktree, **clean its build artifacts**: each worktree creates its own per-checkout artifacts (dependency directory, build/output cache, compiled targets — e.g. `node_modules`, `target/`, `.venv`, a build cache). The `/fix-issue` skill's multi-issue mode includes the cleanup pass; replicate it.
- Never give two concurrent agents the same worktree. One worktree = one writer.
- The main checkout's working tree must be clean before spawning a worktree-based agent — pre-existing dirty state poisons the agent's git context.

## Worktree cwd discipline (binding for every worktree-isolated agent)

**Failure mode.** When the orchestrator spawns a subagent with `Agent(subagent_type: claude, isolation: worktree, ...)`, the Agent harness creates the worktree but does **NOT** set the spawned subprocess's initial cwd to the worktree path. The agent's Bash tool starts with `cwd = orchestrator's cwd` (the main checkout). The agent must explicitly `cd "<worktree-path>"` at the start of **every** Bash call. The Bash tool persists cwd between calls in a single session, but a single early call from the wrong cwd writes files to the wrong place — stray files land in the main checkout, get accidentally committed or referenced, and produce a build that fails on any clean clone with missing-file / unresolved-reference errors.

**Standing precedent.** This is a recurring class of bug in worktree-isolated agent workflows: a subagent issues an early Bash call from the orchestrator's main checkout instead of its worktree, so the RED→GREEN cycle (or a file write) lands in the wrong tree. The two failure shapes seen in practice:

- **Stray files committed into main**: the agent's branch ends up referencing source files that were written into the main checkout and never git-tracked on the branch. Result: a build that passes locally for the agent but fails on a clean clone with missing-file / unresolved-reference errors. Requires a dedicated hotfix PR to restore main.
- **Self-rescue mid-flow**: a more careful agent catches the drift, saves its diff to `/tmp`, reverts the main checkout, then re-applies the patch inside the worktree on the proper branch before committing. No contamination ships — but only because the agent noticed.

The tested workaround: **every brief includes an explicit "cd "<worktree-path>" first" discipline in its preamble, and contamination does not recur for agents that receive that discipline.** This subsection codifies that workaround into a rule.

**Mandate.** Every worktree-isolated agent's brief MUST include a "Critical Operational" preamble that:

1. States the exact worktree path the agent is expected to operate inside.
2. Requires `cd "<worktree-path>"` at the **start of every `Bash` tool call** — not just the first one. (A single later call that omits the prefix can silently land work in the main checkout.)
3. Requires `pwd` confirmation in the first Bash call, before any edit or write, so the agent fails loudly if it's not where it expects to be.
4. Names the consequence explicitly so the agent treats the discipline as load-bearing, not decorative: contaminating main produces broken builds on clean clones (missing-file / unresolved-reference errors) and costs a hotfix PR.

This requirement applies to **every** worktree-isolated agent spawn — feature agents, bugfix agents, audit subagents, verification subagents. There is no "small task" exemption; the contamination cost is the same whether the agent writes one file or twenty.

**Copy-pasteable preamble template** (orchestrators: paste verbatim into the brief, substituting the worktree path):

```
## CRITICAL OPERATIONAL — binding

Your worktree path is: <ABSOLUTE-WORKTREE-PATH>

Every `Bash` tool call you issue MUST begin with `cd "<ABSOLUTE-WORKTREE-PATH>"`.
Before your first edit or write, run `pwd` and confirm it prints the worktree
path. If `pwd` does NOT match, stop and report — do NOT attempt to recover by
guessing.

The Agent harness creates the worktree but does NOT set your initial cwd to
it. Your Bash tool starts with cwd = the orchestrator's main checkout
(`<ABSOLUTE-MAIN-CHECKOUT-PATH>`). A single Bash call that forgets the `cd`
prefix can write to the main checkout instead of your worktree; stray files
then get committed or referenced and break the build on every clean clone with
missing-file / unresolved-reference errors. Standing precedent: this class of
contamination has required hotfix PRs to restore main, and careful agents have
had to self-rescue from the same drift mid-flow.

This is binding for every Bash call, not just the first. Do not skip this in
the interest of brevity.
```

**Orchestrator checklist when spawning a worktree-isolated agent.** Before sending the brief:

- [ ] The brief includes the "Critical Operational" preamble (or an equivalent that names the cwd, the `pwd` confirmation, and the consequence).
- [ ] The worktree path is the **absolute** path, not a relative one.
- [ ] If the brief includes multi-step bash sequences, every step starts with `cd "<worktree-path>"` (compound commands `cd X && Y && Z` are fine — what's not fine is a later Bash call that omits the prefix and assumes the previous call's cwd persists).
- [ ] If the agent reports something that smells like contamination (`git status` in the main checkout shows files the agent shouldn't have written, or the branch imports modules whose source isn't tracked on the branch), treat the agent's output as suspect and verify by inspecting the main checkout's working tree before merging.

## Worked examples

**Good — mixed gates, `#46 WI-0a + #48 planning`**:
- Main agent on `feat/46-wi-0a-...` branch implementing production code (Gate 3).
- Spawned read-only subagent reading 14 files + writing one markdown plan to `dev-docs/plans/20260503-feature-48-...md` (Gate 1).
- No file-write overlap. Subagent's output reviewed and integrated by main agent.

**Good — `/fix-issue` multi-issue mode**:
- N issues, N worktrees, N agents. Each runs its own pipeline. Cleanup pass removes stale per-checkout build artifacts after each worktree is removed.

**Bad — would have been wrong**:
- `#46` and `#47` in parallel: hard dependency (`#47` needs `#46`'s boundary-interface shape). Tracker says so explicitly. Parallelizing would have wasted `#47`'s implementation.

**Bad — would have been wrong**:
- Spawning a subagent with prompt "implement WI-0a, you have full context" — context absorption fails; the subagent will misremember type names and produce code that doesn't build.

## What this rule does NOT cover

- Per-PR parallelism (CI runs across PRs) — handled by the CI infrastructure, not this rule.
- Agent-to-agent communication mid-flight — out of scope; subagents are fire-and-forget with single return.
