#!/usr/bin/env bash
#
# WI-ID linkage check (rule 60 §2).
#
# Mechanism: a plan file at dev-docs/plans/*.md defines work items as headings
# of the form `**WI-N.M — title**`. Once a WI is implemented, the implementer
# must mention its ID at least once in:
#   (a) a commit message on the current branch, OR
#   (b) a top-of-file comment in the test file that covers it
#
# This script scans the plan, extracts every WI-ID, and verifies the linkage.
# Drift detection: if a WI-ID is missing both, you've shipped without a trace.
#
# Usage:
#   bash scripts/check-wi-linkage.sh <plan-file> [--phase=N]
# Example:
#   bash scripts/check-wi-linkage.sh dev-docs/plans/20260504-my-feature.md --phase=1
#
# Without --phase, every WI in the plan is checked. With --phase=N, only WIs
# whose ID matches WI-N.* are checked. --phase is the manual stand-in for
# "only WIs in a completed phase": run it per phase as that phase completes,
# since later, not-yet-started phases will legitimately be unlinked.
#
# Exit codes:
#   0  every checked WI-ID found in either commits or test headers
#   1  one or more WI-IDs missing
#  64  bad invocation
#
# Stack-agnostic: test-file discovery matches the kit's conventions
# (foo.test.*, foo.spec.*, foo_test.*, test_foo.*) across any language —
# the same patterns the tdd-guard hook uses. "Current branch" means commits
# since the merge-base with the trunk (main/master, or $TRUNK_BRANCH).

set -uo pipefail

cd "$(dirname "$0")/.."

PLAN=""
PHASE_FILTER=""
for arg in "$@"; do
  case "$arg" in
    --phase=*) PHASE_FILTER="${arg#--phase=}" ;;
    -*) echo "unknown flag: $arg"; exit 64 ;;
    *) PLAN="$arg" ;;
  esac
done

if [[ -z "$PLAN" ]]; then
  echo "Usage: $0 <plan-file> [--phase=N]"
  exit 64
fi
if [[ ! -f "$PLAN" ]]; then
  echo "plan file not found: $PLAN"
  exit 64
fi

# Base WI pattern used to scan commit messages and test headers (any WI).
BASE_WI_RE="WI-[0-9]+(\.[0-9]+)?[a-z]?"

# Pattern used to extract the plan's WI list — narrowed when --phase is set.
PATTERN="$BASE_WI_RE"
if [[ -n "$PHASE_FILTER" ]]; then
  PATTERN="WI-${PHASE_FILTER}(\.[0-9]+)?[a-z]?"
fi

# Extract WI-IDs from the plan. The convention is **WI-N.M — title**; WI-N
# (no minor) is accepted too. Bash 3.2-compatible array fill (macOS /bin/bash).
WIS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && WIS+=("$line")
done < <(grep -E -o "$PATTERN" "$PLAN" | sort -u)

if (( ${#WIS[@]} == 0 )); then
  echo "no WI-IDs matching pattern '$PATTERN' found in $PLAN"
  exit 0
fi

# Determine merge-base. On the trunk itself, fall back to the previous tag.
TRUNK="${TRUNK_BRANCH:-}"
BASE=""
if git rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$BRANCH" == "main" || "$BRANCH" == "master" || ( -n "$TRUNK" && "$BRANCH" == "$TRUNK" ) ]]; then
    BASE=$(git describe --tags --abbrev=0 2>/dev/null || git rev-parse HEAD~50 2>/dev/null || echo "")
  else
    [[ -n "$TRUNK" ]] && BASE=$(git merge-base HEAD "$TRUNK" 2>/dev/null || echo "")
    [[ -z "$BASE" ]] && BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || echo "")
  fi
fi
RANGE="$BASE..HEAD"
[[ -z "$BASE" ]] && RANGE="HEAD"

# Commit-message blob for the range.
COMMIT_LOG=$(git log --pretty=format:"%s%n%b" "$RANGE" 2>/dev/null || echo "")

# Test-file headers: scan the first 30 lines of every test file for WI refs.
# Stack-agnostic discovery — matches foo.test.<ext>, foo.spec.<ext>,
# foo_test.<ext>, test_foo.<ext> in any language, pruning vendored/build dirs.
TEST_HEADERS=$(
  find . \
    \( -type d \( -name node_modules -o -name .git -o -name dist -o -name build \
       -o -name coverage -o -name vendor -o -name target -o -name .venv \
       -o -name __pycache__ \) -prune \) -o \
    -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.*' -o -name 'test_*' \) -print 2>/dev/null \
  | while IFS= read -r f; do head -n 30 "$f" 2>/dev/null; done \
  | grep -E -o "$BASE_WI_RE" | sort -u
)

ok()   { echo "  ✓ $1"; }
miss() { echo "  ✗ $1"; }

LINKED=0
MISSING=()
for wi in "${WIS[@]}"; do
  in_commit=0
  in_test=0
  echo "$COMMIT_LOG"   | grep -F -q "$wi" && in_commit=1
  echo "$TEST_HEADERS" | grep -F -q "$wi" && in_test=1
  if (( in_commit + in_test > 0 )); then
    LINKED=$((LINKED+1))
    src="commit"
    (( in_test == 1 )) && (( in_commit == 0 )) && src="test"
    (( in_test == 1 )) && (( in_commit == 1 )) && src="commit+test"
    ok "$wi linked ($src)"
  else
    MISSING+=("$wi")
    miss "$wi NOT linked (no commit, no test header)"
  fi
done

echo
echo "─────────────────────────────────────────────"
echo "Plan: $PLAN"
echo "WIs found: ${#WIS[@]}    linked: $LINKED    unlinked: ${#MISSING[@]}"
echo "Commit range: $RANGE"

if (( ${#MISSING[@]} > 0 )); then
  echo
  echo "Unlinked WIs (each must appear in a commit message OR test-file header):"
  for w in "${MISSING[@]}"; do echo "  • $w"; done
  echo
  echo "Two ways to link a WI:"
  echo "  • Commit message:  feat(scope): wire the parser orchestrator (WI-1.2)"
  echo "  • Test header:     // WI-1.2 — orchestrator dispatch tests   (or  # WI-1.2 — … in #-comment languages)"
  exit 1
fi
exit 0
