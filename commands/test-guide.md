# Manual Testing Guide

Open the comprehensive testing guide and help the user test this project's features.

## Instructions

1. Read the testing guide at `dev-docs/testing/comprehensive-testing-guide.md` (create the directory if it does not yet exist)
2. Present a summary of test categories to the user
3. If the user specifies a category, show those specific tests
4. Help track test results if requested

## Test Categories

Enumerate this project's own feature areas as the test categories. Derive
them from the project's tracker (`docs/features.md`), its module/package
layout, and the user-facing flows it exposes. For each category, list the
behaviors to exercise and the expected outcome.

A useful starting set — adapt to whatever this project actually does:

1. **Core feature flows** — the project's primary happy-path behaviors end to end
2. **Input / output fidelity** — output is correct and the meaningful structure of the input is preserved
3. **Configuration & state** — settings, modes, and persisted state behave and survive restarts
4. **Integration / external boundaries** — calls to external services or dependencies succeed, switch correctly, and degrade gracefully
5. **Long-running / streaming operations** — progressive output, cancellation mid-operation, and clean resource teardown
6. **Error & failure states** — missing/invalid config, timeouts, network failure, and downstream errors are surfaced clearly; secrets never leak
7. **Localization / i18n** (if applicable) — UI/output strings localize correctly and switching locale updates everything
8. **Edge-case input handling** — boundary values, empty/null, very large input, and unusual character sets render and behave correctly

## Quick Start

Ask the user which category they want to test, then:
1. Show the relevant test cases from the guide
2. Help them execute tests by running the app the way this project runs it (CLI, server, desktop, browser, or a library test harness, whatever applies); automate with the project's E2E tool if it has one
3. Record results

## Files

- Main guide: `dev-docs/testing/comprehensive-testing-guide.md`
- Add per-area detail files alongside it as the project grows (e.g. `dev-docs/testing/<feature-area>-testing.md`)
