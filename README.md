# claude-kit

A **stack-agnostic Claude Code plugin** — the process/methodology backbone (agents, slash
commands, skills, workflow hooks, and process rules) that works on *any* coding project,
regardless of language, framework, or domain. Distilled from real project `.claude/` setups
and generalized so nothing is tied to a particular stack.

It gives you a gated feature workflow, test-first discipline, planning/audit/verify agents,
GitHub issue & PR flows, cross-model (Codex) review, and a set of safety hooks — all driven
by your project's *own* configured commands, not hardcoded ones.

## Install

```sh
# 1. Add the marketplace that hosts the companion plugins this kit depends on
/plugin marketplace add xiaolai/claude-plugin-marketplace

# 2. Add this kit's marketplace, then install it (pulls its dependencies automatically)
/plugin marketplace add lllyys/claude-kit
/plugin install claude-kit@lllyys
```

Installing `claude-kit` automatically installs its four companion plugins (see
[Dependencies](#dependencies)). Step 1 is required so those cross-marketplace
dependencies can resolve.

## What's included

| Component | Count | What it is |
|---|---|---|
| **agents/** | 9 | `planner`, `implementer`, `auditor`, `verifier`, `test-runner`, `spec-guardian`, `impact-analyst`, `release-steward`, `manual-test-author` — the roles the workflow delegates to. |
| **commands/** | 10 | `/feature-workflow`, `/fix`, `/fix-issue`, `/merge-prs`, `/repo-clean-up`, `/test-guide`, `/file-bug`, `/file-feature`, `/cron-bootstrap`, `/bump`. |
| **skills/** | 15 | `planning`, `plan-audit`, `plan-verify`, `feature-workflow`, `fix-issue`, `file-bug`, `file-feature`, `triage`, `verify`, `release-gate`, `ai-coding-agents`, `cc-suite`, `mcp-dev`, `mcp-server-manager`, `workflow-audit`. |
| **hooks/** | 8 + `hooks.json` | Prompt-refinement, evidence/issue-mirror gates, a TDD guard, a Codex-audit merge gate, and stop-time checks — wired via `hooks/hooks.json`. |
| **rules/** | 10 | Engineering principles, TDD, doc/comment sync, version bump, the binding 6-gate feature workflow, parallel execution, background shells, Codex-runner isolation, and AI governance. Shipped as bundled docs (see [Activating the rules](#activating-the-rules)). |
| **cron-prompts/** | 4 | `bugfix`, `feature`, `verify`, `watchdog` prompts for scheduled-agent runs (via `/cron-bootstrap`). |

Commands, agents, skills, and hooks activate automatically once the plugin is enabled.

## Activating the rules

Claude Code plugins have no native `rules/` component, so the kit ships its process rules as
**bundled docs** you opt into. Copy them into your project and `@import` them from your
`CLAUDE.md` so they load as always-on guidance:

```sh
# from a clone of this repo (or the installed plugin directory)
cp -r rules .claude/rules
```

Then in your project's `CLAUDE.md`:

```markdown
@.claude/rules/00-engineering-principles.md
@.claude/rules/10-tdd.md
@.claude/rules/47-feature-workflow.md
@.claude/rules/60-ai-governance.md
# …import the rules you want
```

Copying them to `.claude/rules/` keeps the rules' cross-references resolvable and lets you
tune any of them per project.

## Per-project configuration

The kit is driven by *your* project's commands and paths — set these up once:

1. **Test / coverage commands** — copy `examples/tdd-guardian/config.json` to
   `.claude/tdd-guardian/config.json` and set `testCommand`, `coverageCommand`, and `stack`.
   Everything that "runs the tests" or "checks coverage" reads from here.
2. **Docs coverage** — copy `examples/docs-guardian/config.json` to
   `.claude/docs-guardian/config.json` and map your code paths → doc pages.
3. **File-size limits** (optional) — copy `examples/loc-guardian.local.md` to
   `.claude/loc-guardian.local.md`.
4. **High-risk TDD paths** — the `tdd-guard.mjs` hook ships with an **empty** scope (so it
   blocks nothing by default). To enforce test-first on critical paths, set them in your copy
   of the hook, e.g. `SCOPED = ['src/payments/', 'src/auth/']`.
5. **Tracker conventions** (used by several commands/hooks, create as needed):
   `docs/features.md`, `docs/bugs.md`, plans in `dev-docs/plans/`, verification evidence in
   `dev-docs/verification/`, and Codex audit artifacts in `.claude/codex-audits/`.

## Dependencies

`claude-kit` declares hard dependencies on four companion plugins (all from the `xiaolai`
marketplace), installed automatically:

- **cc-suite** — Claude ↔ Codex ↔ Gemini bridging and cross-model delegation/audit.
- **tdd-guardian** — strict TDD enforcement and coverage gates.
- **docs-guardian** — documentation staleness/coverage/accuracy.
- **claude-english-buddy** — writing-quality feedback.

## What's intentionally excluded

To stay universal, the following were left out (they're stack- or domain-specific):

- UI/frontend rules (design tokens, focus indicators, dark theme, component patterns).
- Domain rules (e.g. an app's LLM-provider layer).
- Framework skills (`react-app-dev`, `css-design-tdd`) and any single-ecosystem helpers.

## Layout

```
claude-kit/
├── .claude-plugin/
│   ├── plugin.json        # manifest + dependencies
│   └── marketplace.json   # self-marketplace (this repo installs itself)
├── agents/                # 9 subagents
├── commands/              # 10 slash commands
├── skills/                # 15 skills
├── hooks/                 # hook scripts + hooks.json
├── rules/                 # 10 bundled process rules (opt-in via @import)
├── cron-prompts/          # 4 scheduled-agent prompts
├── examples/              # per-project config templates to copy in
├── LICENSE
└── README.md
```

## License

MIT — see [LICENSE](LICENSE).
