---
description: Fix issues properly - no patches, no shortcuts, no regressions
argument-hint: "[issue description or error message]"
---

# Fix

## Context

```text
$ARGUMENTS
```

## Fixing Philosophy

**No half measures.** Every fix must be complete and correct.

### Principles

1. **Understand before fixing** — Read the code, trace the flow, identify root cause
2. **Fix the cause, not the symptom** — No band-aids, no workarounds, no "good enough"
3. **Rewrite if necessary** — Bad code deserves replacement, not patching
4. **Test-first** — Write a failing test that captures the bug, then fix, then verify green (see `.claude/rules/10-tdd.md`)
5. **Zero regressions** — Run the project's build/gate command before declaring done
6. **Clean as you go** — If you touch it, leave it better than you found it

### Anti-patterns to Avoid

- Adding flags to bypass broken logic
- Wrapping bad code in try-catch to silence errors
- Commenting out problematic code
- Adding TODO for "later"
- Special-casing edge cases without fixing core issue
- Copy-pasting fixes across similar code

## Process

### 1. Reproduce

- Read the relevant source files. Trace the call chain from symptom to root cause.
- Reproduce the bug via a failing test (preferred), or by running the app the way this project runs it — CLI, server, desktop, browser, or a library test harness, whatever applies — and observing the broken behavior.

### 2. Diagnose

- Find the **root cause**, not just where it crashes.
- Check if similar patterns exist elsewhere — the same bug may lurk in related code.

### 3. Test First (RED)

- Write a failing test that captures the bug.
- Follow the pattern catalog in `.claude/rules/10-tdd.md`:
  - Integration-boundary bug → test the module's public interface against mocked dependencies (no real external service)
  - Data-transform / pipeline bug → table-driven tests over input → expected output, covering the broken case
  - State / store bug → assert the state transition directly
  - UI / component bug → render the unit with mocked dependencies and assert behavior
- Exception: purely visual bugs (e.g. styling/layout) may not warrant a unit test — use manual visual QA instead.

### 4. Fix Properly (GREEN)

- Address the root cause. Rewrite if the existing code is fundamentally flawed.
- Keep the diff minimal and focused — don't refactor unrelated code.
- Follow the project's own conventions (import style, naming, layering, styling/theming, module boundaries) and keep files reasonably small (~300 lines).

### 5. Refactor

- Clean up without changing behavior. Tests must still pass.
- Remove dead code. Update comments if they're now stale.

### 6. Verify

- Run the project's build/gate command — lint, coverage thresholds, and build must all pass.
- If user-facing behavior changed, verify it by running the app the way this project runs it (CLI, server, desktop, browser, or a library test harness, whatever applies) and observing the behavior; automate with the project's E2E tool if it has one.
- If user-facing behavior changed, update docs as needed.

### When to Rewrite vs Patch

**Rewrite when:**
- The existing code is fundamentally flawed
- Patching would add complexity
- The fix requires understanding fragile logic
- Similar bugs have occurred in this code before

**Patch only when:**
- The code is sound but has a small oversight
- The fix is isolated and obvious
- Rewriting would introduce unnecessary risk
