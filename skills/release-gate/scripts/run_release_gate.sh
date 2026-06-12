#!/usr/bin/env bash
set -euo pipefail

# Release gate runner — runs the project's configured quality gate:
#   lint -> tests (with coverage) -> build
#
# Test/coverage commands are read from .claude/tdd-guardian/config.json
# (coverageCommand, falling back to testCommand). Lint and build are the
# project's own commands — set them via env vars or fill in the PLACEHOLDERs
# below.
#
# Usage: run_release_gate.sh [LOG_PATH]
#   LOG_PATH  optional file to tee combined output into.

LOG_PATH="${1:-}"

# This script ships with the claude-kit plugin (under
# ${CLAUDE_PLUGIN_ROOT}/skills/release-gate/scripts/), so it can't derive the
# adopter's repo root from its own location. Resolve the repo root from the
# project's working tree instead (git top-level, falling back to cwd). The
# tdd-guardian config lives in the adopter's project at .claude/tdd-guardian/.
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG_PATH="$REPO_ROOT/.claude/tdd-guardian/config.json"

# Read a string field from the config without requiring jq.
read_config_field() {
  local field="$1"
  [[ -f "$CONFIG_PATH" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg f "$field" '.[$f] // ""' "$CONFIG_PATH" 2>/dev/null || true
  else
    # Minimal fallback parser: "field": "value"
    sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$CONFIG_PATH" | head -n1
  fi
}

# Test/coverage command: prefer coverageCommand, fall back to testCommand.
COVERAGE_CMD="$(read_config_field coverageCommand)"
TEST_CMD="$(read_config_field testCommand)"
TEST_STEP="${COVERAGE_CMD:-$TEST_CMD}"

# PLACEHOLDER: set your project's lint and build commands here, or export
# LINT_CMD / BUILD_CMD before invoking. Leave empty to skip the step.
LINT_CMD="${LINT_CMD:-}"   # e.g. "npm run lint", "cargo clippy", "ruff check ."
BUILD_CMD="${BUILD_CMD:-}" # e.g. "npm run build", "cargo build --release", "make"

if [[ -z "$TEST_STEP" ]]; then
  echo "release-gate: no testCommand/coverageCommand in $CONFIG_PATH — configure it first." >&2
  exit 1
fi

run_gate() {
  if [[ -n "$LINT_CMD" ]]; then
    echo "==> lint: $LINT_CMD"
    eval "$LINT_CMD"
  else
    echo "==> lint: (no LINT_CMD configured — skipped)"
  fi

  echo "==> test+coverage: $TEST_STEP"
  eval "$TEST_STEP"

  if [[ -n "$BUILD_CMD" ]]; then
    echo "==> build: $BUILD_CMD"
    eval "$BUILD_CMD"
  else
    echo "==> build: (no BUILD_CMD configured — skipped)"
  fi
}

if [[ -n "$LOG_PATH" ]]; then
  run_gate | tee "$LOG_PATH"
else
  run_gate
fi
