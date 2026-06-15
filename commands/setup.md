---
description: Set up claude-coding-kit in this project — detect the tech stack, confirm the commands, then write the TDD/guardian config, copy the process rules in (wired via @import), set the high-risk TDD paths, and scaffold the trackers. Run once when adopting the kit; safe to re-run.
---

# /setup — set up claude-coding-kit for this project

Bootstrap everything claude-coding-kit needs in the **current project**: detect the stack, confirm
the commands with the user, then write config and scaffolding. **Idempotent** — re-running
updates existing files in place rather than duplicating, and never clobbers the user's own
edits without backing them up first.

Work through the steps in order. Do not write any files until after Step 3 (confirmation).

## Step 1 — Locate the kit and the project

- **Project root** = where Claude Code was launched: `${CLAUDE_PROJECT_DIR:-$PWD}`. All
  config and scaffolding goes here.
- **Kit source** (rules + config templates) ships with the plugin at `${CLAUDE_PLUGIN_ROOT}`.
  If that variable is unset in the shell, find the install dir (the directory containing this
  repo's `rules/` and `examples/`) before continuing — do not guess paths.

## Step 2 — Detect (or declare) the tech stack

Scan the project root for manifest files and infer the language, package manager, and
commands, using the table below. Handle three cases:

- **One manifest** → detect from it.
- **Several manifests** → ask the user which is the primary project (or, for a monorepo,
  which package to target).
- **None** — an **empty or freshly-initialized repo** with no manifest yet → do **NOT** fail.
  Switch to *declare* mode: ask the user what stack they intend to use (language + package
  manager + test runner), and derive the commands from the table as if that manifest were
  present. Then offer — but don't force — to **scaffold a starter** so there's something to
  detect next time, e.g. `npm create vite@latest` / `npm init -y`, `uv init` / `poetry init`,
  `cargo init`, `go mod init <module>`, `bundle init`, `dotnet new`, `composer init`, or
  `swift package init`. If the user declines scaffolding, still write the config from the
  declared stack so the kit is configured from the very first commit.

Detection table (also the reference for *declare* mode):

| Manifest | Language | Package manager (lockfile) | Test | Coverage | Build | Lint |
|---|---|---|---|---|---|---|
| `package.json` | JS/TS | pnpm (`pnpm-lock.yaml`) · yarn (`yarn.lock`) · bun (`bun.lockb`) · npm (`package-lock.json`) | `scripts.test`, else `<pm> test` | `scripts["test:coverage"]`, else `<pm> test -- --coverage` | `scripts.build` | `scripts.lint` |
| `pyproject.toml` · `setup.py` · `requirements.txt` · `Pipfile` | Python | uv (`uv.lock`) · poetry (`poetry.lock`) · pip | `pytest` | `pytest --cov` | (build backend, if any) | `ruff check` / `flake8` |
| `Cargo.toml` | Rust | cargo | `cargo test` | `cargo llvm-cov` | `cargo build` | `cargo clippy` |
| `go.mod` | Go | go | `go test ./...` | `go test -cover ./...` | `go build ./...` | `go vet ./...` |
| `Gemfile` | Ruby | bundler | `bundle exec rspec` | `bundle exec rspec` (+ SimpleCov) | `rake build` | `bundle exec rubocop` |
| `*.csproj` · `*.sln` | C#/.NET | dotnet | `dotnet test` | `dotnet test --collect:"XPlat Code Coverage"` | `dotnet build` | `dotnet format --verify-no-changes` |
| `composer.json` | PHP | composer | `composer test`, else `vendor/bin/phpunit` | `phpunit --coverage-text` | — | `vendor/bin/phpcs` |
| `pom.xml` · `build.gradle(.kts)` | Java/Kotlin | maven · gradle | `mvn test` / `gradle test` | `mvn verify` (JaCoCo) / `gradle jacocoTestReport` | `mvn package` / `gradle build` | `gradle check` |
| `Package.swift` · `*.xcodeproj` | Swift | spm · xcodebuild | `swift test` / `xcodebuild test …` | `swift test --enable-code-coverage` | `swift build` | `swiftlint` |

For `package.json`, **read the actual `scripts` block** and prefer real script names over the
generic fallbacks. Note the coverage **summary path** the tooling emits (e.g.
`coverage/coverage-summary.json` for Vitest/Jest with the `json-summary` reporter).

Derive a **gate** command — the chained quality check the kit runs before "done". Prefer an
existing one (e.g. a `check:all` / `ci` script, a `Makefile` target); otherwise compose
`lint && test (with coverage) && build`.

## Step 3 — Confirm with the user

Show the detected stack and the proposed commands (**test · coverage · build · lint · gate**)
and ask the user to confirm or correct each **before writing anything**. If the user is away
or says "use defaults", proceed with the detected values. Also ask, with sensible defaults:

- **High-risk paths** to TDD-gate (e.g. `src/payments/`, `src/auth/`). Default: none.
- **Coverage thresholds** for the gate. Default: `80`. (Offer `100` for strict TDD, `0` to
  measure-but-not-block.)
- Whether to **scaffold trackers** (`docs/features.md`, `docs/bugs.md`). Default: yes.

## Step 4 — Write per-project config (into the project's `.claude/`)

Start each file from the matching template in `${CLAUDE_PLUGIN_ROOT}/examples/`, then fill it
in. If a target file already exists, show a diff and ask before overwriting.

1. **`.claude/tdd-guardian/config.json`** — from `examples/tdd-guardian/config.json`. Set
   `testCommand`, `coverageCommand`, `coverageSummaryPath`, `stack`, `packageManager`, and the
   confirmed `thresholds`.
2. **`.claude/docs-guardian/config.json`** — from `examples/docs-guardian/config.json`. Map the
   detected source dir → a docs page (sensible defaults; the user refines later).
3. **`.claude/loc-guardian.local.md`** — from `examples/loc-guardian.local.md` (language-neutral
   file-splitting guidance; keep as-is unless the user wants tuning).
4. **`.claude/tdd-guard.paths.json`** — a JSON array of the high-risk path prefixes from
   Step 3, e.g. `["src/payments/", "src/auth/"]` (or `[]` if none). The kit's `tdd-guard` hook
   reads this file; an empty array leaves the guard disabled.

## Step 5 — Copy the process rules in and wire them

The kit's rules are bundled docs, opted into via `@import` (Claude Code plugins have no native
`rules/` component).

1. **Copy the rules into the project**:
   `cp -R "${CLAUDE_PLUGIN_ROOT}/rules" .claude/rules`
   — if `.claude/rules` already exists, back it up (`.claude/rules.bak-<timestamp>`) before
   copying so local edits aren't lost.
2. **Wire them into the project's `CLAUDE.md`** (create it if absent). Add or refresh a single
   managed block so re-running stays idempotent:

   ```markdown
   <!-- claude-coding-kit:rules (managed — edit the import list, not the markers) -->
   @.claude/rules/00-engineering-principles.md
   @.claude/rules/05-design-before-coding.md
   @.claude/rules/06-no-self-designed-ui.md
   @.claude/rules/10-tdd.md
   @.claude/rules/20-logging-and-docs.md
   @.claude/rules/22-comment-maintenance.md
   @.claude/rules/40-version-bump.md
   @.claude/rules/47-feature-workflow.md
   @.claude/rules/48-parallel-execution.md
   @.claude/rules/49-background-shells.md
   @.claude/rules/53-codex-runner-isolation.md
   @.claude/rules/60-ai-governance.md
   <!-- /claude-coding-kit:rules -->
   ```

   Offer to import a subset if the user prefers. Also add a one-line **stack note** near the
   top of `CLAUDE.md` (detected language, package manager, and the test/gate commands) so the
   stack is visible without opening a config file.

## Step 6 — Scaffold trackers & directories (if confirmed)

- `docs/features.md` and `docs/bugs.md` — each with a short header and the **six-column**
  status table the kit's commands and hooks parse:
  `| ID | Title | Area | Priority | Status | Notes |`.
  All six columns are required: the `check_gh_issue_mirror.sh` and
  `check_terminal_status_evidence.sh` hooks skip any row with fewer than six
  cells, so a four-column table silently leaves those gates non-functional.
- `dev-docs/plans/.gitkeep`, `dev-docs/verification/.gitkeep`, `.claude/codex-audits/.gitkeep`.

Create only what's missing; never overwrite an existing tracker.

## Step 7 — Verify the companion plugins

Confirm the four dependency plugins are installed and enabled: **cc-suite**, **tdd-guardian**,
**docs-guardian**, **claude-english-buddy**. They install automatically with claude-coding-kit; if any
is missing, tell the user how to install it rather than proceeding silently.

## Step 8 — Summarize

Report a checklist of **every file created or updated**, the **detected commands** the user
should double-check, and any decision left at a default. Call out specifically:

- Review `.claude/tdd-guardian/config.json` — the `testCommand` / `coverageCommand` are the
  load-bearing settings.
- The high-risk paths in `.claude/tdd-guard.paths.json` (empty = TDD guard off).
- The `@import` block added to `CLAUDE.md`.

End with the natural next step: `/feature-workflow` to build something, or `/triage` to
process an issue.
