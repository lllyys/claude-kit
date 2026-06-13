#!/usr/bin/env node
//
// PreToolUse hook: scoped TDD guard for this project's high-risk paths.
// Blocks Write/Edit on production source files unless a sibling
// test file exists.
//
// Scope (intentionally narrow to the high-risk layers you configure):
//   Project high-risk paths come from
//   <project>/.claude/tdd-guard.paths.json (a JSON array of path
//   prefixes). `/init` writes it; an empty/absent file disables the guard.
//
// Behavior:
//   - For a Write/Edit/MultiEdit targeting a file in scope:
//     - If the file is itself a test file, allow (we're writing tests).
//     - If the file is a type-only / declaration file, allow.
//     - Otherwise: require a sibling test file to exist.
//       - If sibling does not exist, BLOCK with exit 2 and a clear message.
//       - If sibling exists, allow.
//
// This is a structural test, not a "is the test currently failing" test.
// Later work can layer on a stricter check (run the project's test
// command, look for at least one fail, block if none) once tests exist.
//
// Reading the hook input (Claude Code passes JSON on stdin):
//   { tool_name, tool_input: { file_path, ... }, ... }
//
// Exit codes (Claude Code convention):
//   0 — allow
//   2 — block; stderr is shown to the agent
//   other — error; advisory, does not block

import { readFileSync, existsSync } from "node:fs";
import { resolve, dirname, basename, extname } from "node:path";

// ── Read JSON from stdin ────────────────────────────────────────────────
let payload;
try {
  payload = JSON.parse(readFileSync(0, "utf8"));
} catch (e) {
  // Cannot parse — let the tool call through; this hook is advisory then.
  process.exit(0);
}

const tool = payload.tool_name ?? payload.toolName ?? "";
const input = payload.tool_input ?? payload.toolInput ?? {};
const filePath = input.file_path ?? input.filePath ?? "";

// Only relevant for Write / Edit / MultiEdit on filesystem paths.
if (!["Write", "Edit", "MultiEdit", "NotebookEdit"].includes(tool)) {
  process.exit(0);
}
if (!filePath || typeof filePath !== "string") {
  process.exit(0);
}

const abs = resolve(filePath);
// In plugin form this hook runs from the plugin's install dir, so derive the
// PROJECT root from the environment (Claude Code sets CLAUDE_PROJECT_DIR).
const repoRoot = process.env.CLAUDE_PROJECT_DIR
  ? resolve(process.env.CLAUDE_PROJECT_DIR)
  : process.cwd();

// Convert to a path relative to repo root for scope matching.
const rel = abs.startsWith(repoRoot + "/") ? abs.slice(repoRoot.length + 1) : abs;

// ── Scope check ─────────────────────────────────────────────────────────
// High-risk paths are configured per project in
//   <project>/.claude/tdd-guard.paths.json
// a JSON array of path prefixes (relative to the project root), e.g.
//   ["src/payments/", "src/auth/"]
// `/init` writes this file. If it is absent or empty, the guard is disabled.
let SCOPED = [];
try {
  const raw = readFileSync(resolve(repoRoot, ".claude/tdd-guard.paths.json"), "utf8");
  const parsed = JSON.parse(raw);
  if (Array.isArray(parsed)) {
    SCOPED = parsed.filter((p) => typeof p === "string" && p.length > 0);
  }
} catch {
  // No config (or unreadable) → empty scope → guard disabled.
}

// Empty scope → nothing to guard; allow.
if (SCOPED.length === 0) {
  process.exit(0);
}

const inScope = SCOPED.some((p) => rel.startsWith(p));
if (!inScope) {
  process.exit(0);
}

// ── Allow-list within scope ─────────────────────────────────────────────
//   - Test files themselves
//   - Type-only / declaration files
//   - Stylesheet / asset files (no test required)
const base = basename(rel);

// Common test-file naming conventions across languages:
//   foo.test.ext, foo.spec.ext, foo_test.ext, test_foo.ext
const TEST_FILE_RE = /(\.test\.|\.spec\.|_test\.)/;
const TEST_PREFIX_RE = /^test_/;

// Explicit test file — always allow.
if (TEST_FILE_RE.test(base) || TEST_PREFIX_RE.test(base)) process.exit(0);

// Type-only / declaration allowance (TS .d.ts, common types modules).
if (/^types\.[^.]+$/.test(base)) process.exit(0);
if (base.endsWith(".d.ts")) process.exit(0);

// Stylesheet files — no test required.
if (/\.(css|scss|sass|less)$/.test(base)) process.exit(0);

// ── Sibling test existence check ────────────────────────────────────────
const dir = dirname(abs);
const ext = extname(base);                    // e.g. ".ts", ".py", ".go"
const stem = ext ? base.slice(0, -ext.length) : base; // basename minus extension

// Accept the common sibling test conventions, in the same directory and
// in a parallel `__tests__` / `tests` directory:
//   foo.test.<ext>, foo.spec.<ext>, foo_test.<ext>, test_foo.<ext>
const stems = [
  `${stem}.test${ext}`,
  `${stem}.spec${ext}`,
  `${stem}_test${ext}`,
  `test_${stem}${ext}`,
];
const dirs = [dir, `${dir}/__tests__`, `${dir}/tests`];
const candidates = [];
for (const d of dirs) {
  for (const s of stems) {
    candidates.push(`${d}/${s}`);
  }
}

const found = candidates.find((p) => existsSync(p));
if (found) process.exit(0);

// ── Block ───────────────────────────────────────────────────────────────
const msg = [
  "",
  "  TDD gate (tdd-guard): no test file found for this source.",
  "",
  `  Source:    ${rel}`,
  "  Expected one of:",
  ...candidates.map((p) => `    - ${p.replace(repoRoot + "/", "")}`),
  "",
  "  Per .claude/rules/10-tdd.md, RED comes before GREEN.",
  "  Write the failing test first, then this hook will allow the source edit.",
  "",
  "  This guard is scoped to the high-risk paths in",
  "  .claude/tdd-guard.paths.json. Other source is not affected.",
  "",
].join("\n");

process.stderr.write(msg);
process.exit(2);
