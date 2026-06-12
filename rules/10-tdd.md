# 10 - TDD Workflow

Test-Driven Development is the default discipline for all behavior changes. Where the project enforces coverage thresholds, dropping coverage makes the project's gate fail — writing code without tests breaks the gate.

## Core Discipline: RED → GREEN → REFACTOR

1. **RED** — Write a failing test that describes the expected behavior.
2. **GREEN** — Write the minimum code to make the test pass.
3. **REFACTOR** — Clean up without changing behavior. Tests must still pass.

Never skip RED. If you write code first, you don't know your test actually catches regressions.

## When Tests Are Required

| Category | Required? | Examples |
|----------|-----------|---------|
| State / data management | **ALWAYS** | State transitions, queries/selectors, persistence |
| Side-effect units | **ALWAYS** | I/O, event handling, lifecycle, resource cleanup |
| Utils / helpers | **ALWAYS** | Pure functions, parsers, formatters |
| Integration boundaries | **ALWAYS** | Request mapping, streaming, error/timeout/abort paths |
| Business logic | **ALWAYS** | Domain decisions, validation, merge/conflict rules |
| Bug fixes | **ALWAYS** | Regression test proving the fix |
| Edge cases | **ALWAYS** | Empty input, null, boundary values, concurrency |
| Presentation-only changes | No | Visual/style QA against a reference instead |
| Docs / config | No | Markdown, config-file changes |
| Type-only changes | No | Type/interface additions with no runtime effect |
| UI / view units | Case-by-case | Test behavior (interaction, accessibility), not rendering |

## Test Categories (Assertion Levels)

Match the assertion strength to what the unit-under-test actually guarantees. Stronger is better when the contract is precise; weaker is appropriate when the output is intentionally non-deterministic.

1. **Exact** — Assert the precise value/shape. Use for pure functions, deterministic transforms, and parsers. The strongest signal; prefer it whenever the output is fully determined by the input.
2. **Structural / behavioral** — Assert observable behavior or invariants (state changed, side effect fired, an item appears in a collection, a callback was invoked with the right argument) rather than the full literal output. Use when internals may legitimately vary.
3. **Boundary / property** — Assert that constraints hold across a range (never negative, always sorted, idempotent on re-run, output within bounds). Use for inputs you can't enumerate exhaustively.
4. **Smoke / liveness** — Assert only that the unit ran without throwing or produced *something* well-formed. The weakest level; acceptable only for genuinely non-deterministic output (e.g. a generated/streamed result whose exact text isn't fixed). Never let smoke-level stand in for behavior you *can* pin down.

Rule of thumb: reach for the strongest level the contract allows. A smoke test where an exact assertion was possible is a missed regression catcher.

## How to Write a Good Test (stack-neutral guidance)

These principles hold in any language, framework, or test runner:

- **Isolate each test.** Reset shared state before each test so order never matters.
- **Mock only at boundaries.** Stub the network, filesystem, clock, or external services — never the logic you're trying to verify, and never the vendor SDK's internals when you can stub the transport beneath it.
- **Assert against your own contract**, not a third party's wire shape. Test the interface your code exposes.
- **Drive units directly** where the framework allows — exercise a function/handler/store action without spinning up the whole app when you don't need to.
- **Use table-driven / parameterized tests** for pure functions with many input→output cases: exhaustive and readable, all branches in one place.
- **Cover the unhappy paths** every time: empty input, null/absent values, errors, timeouts, cancellation/abort, and boundary values.
- **For interactive UI units**, query by accessibility role/name (not internal selectors or test-ids), simulate real user interaction, and assert the resulting behavior — not the rendered markup.

## Anti-Patterns — What NOT to Do

| Anti-pattern | Why it's wrong | Do this instead |
|-------------|----------------|-----------------|
| Write code first, tests after | You can't verify your test catches regressions | RED first — always |
| "It runs without crashing" as the only assertion | Tests nothing meaningful | Test specific behavior or output |
| Testing implementation details | Breaks on refactor | Test observable behavior (state, output, effects) |
| Mocking everything | Tests prove nothing | Mock boundaries (APIs, filesystem, clock), not logic |
| Skipping edge cases | Bugs live at boundaries | Empty input, null, max values, concurrent access |
| Snapshot tests for logic | Brittle, auto-updated without review | Use explicit assertions |
| Loose/untyped test data | Hides type errors | Use proper types even in tests |
| Smoke test where exact was possible | Misses real regressions | Use the strongest assertion level the contract allows |

## Running Tests and the Gate

- **Run the tests:** use the project's test command (see `.claude/tdd-guardian/config.json` → `testCommand`).
- **Check coverage:** use the project's coverage command (see `.claude/tdd-guardian/config.json` → `coverageCommand`); review the report for gaps.
- **Full quality gate:** run the project's build/gate command (the release-gate skill runs whatever the project configures — typically lint + tests/coverage + build). All behavior changes must pass the gate before merge.

## File Placement

- Keep tests close to the code they exercise, following the project's prevailing convention (e.g. a sibling test file next to the source, or a dedicated tests directory).
- Group larger suites under a tests subdirectory when a single file gets unwieldy.
- Put shared test helpers/fixtures in one well-known location and reuse them.
