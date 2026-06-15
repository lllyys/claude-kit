#!/usr/bin/env bash
#
# WI-ID linkage check (rule 60 §2).
#
# A plan file at dev-docs/plans/*.md defines work items as bold headings of the
# form `**WI-N.M — title**`. Once a WI is implemented, the implementer must
# mention its ID at least once in EITHER:
#   (a) a commit message on the current branch (since the merge-base with trunk), OR
#   (b) a top-of-file COMMENT in a tracked test file that covers it.
# If a WI is in neither, you've shipped without a trace.
#
# Usage:
#   bash scripts/check-wi-linkage.sh <plan-file> [--phase=N]
#
# Without --phase, every WI heading in the plan is checked. --phase=N (N numeric)
# checks only WI-N.* — the manual stand-in for "only WIs in a completed phase";
# run it per phase as that phase completes.
#
# Exit codes:
#   0  every checked WI-ID found in a commit message or a test-file comment
#   1  one or more WI-IDs missing
#  64  bad invocation
#  65  cannot establish a commit range (no merge-base / no tag) — refuses to
#      scan all of history, which would let unrelated old commits satisfy WIs
#
# Stack-agnostic: test-file discovery matches the kit's conventions
# (foo.test.*, foo.spec.*, foo_test.*, test_foo.*) across any language, limited
# to git-tracked files. Trunk is main/master, or $TRUNK_BRANCH.

set -uo pipefail
cd "$(dirname "$0")/.."

PLAN=""; PHASE_FILTER=""
for arg in "$@"; do
  case "$arg" in
    --phase=*) PHASE_FILTER="${arg#--phase=}" ;;
    -*) echo "unknown flag: $arg"; exit 64 ;;
    *) PLAN="$arg" ;;
  esac
done

[[ -z "$PLAN" ]]  && { echo "Usage: $0 <plan-file> [--phase=N]"; exit 64; }
[[ -f "$PLAN" ]]  || { echo "plan file not found: $PLAN"; exit 64; }
if [[ -n "$PHASE_FILTER" && ! "$PHASE_FILTER" =~ ^[0-9]+$ ]]; then
  echo "--phase must be a non-negative integer (got '$PHASE_FILTER')"; exit 64
fi

BASE_WI_RE="WI-[0-9]+(\.[0-9]+)?[a-z]?"
PATTERN="$BASE_WI_RE"
[[ -n "$PHASE_FILTER" ]] && PATTERN="WI-${PHASE_FILTER}(\.[0-9]+)?[a-z]?"

# Extract WI-IDs only from bold WI headings (**WI-N.M …**) — not prose,
# examples, or fenced code that merely mention a WI.
WIS=()
while IFS= read -r id; do [[ -n "$id" ]] && WIS+=("$id"); done < <(
  grep -E '\*\*WI-[0-9]' "$PLAN" | grep -oE "$PATTERN" | sort -u
)
if (( ${#WIS[@]} == 0 )); then
  echo "no WI headings matching '$PATTERN' in $PLAN"
  exit 0
fi

# Commit range — REQUIRE a resolvable base; never silently scan all history.
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
TRUNK="${TRUNK_BRANCH:-}"
BASE=""
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" || ( -n "$TRUNK" && "$BRANCH" == "$TRUNK" ) ]]; then
  BASE="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"
  if [[ -z "$BASE" ]]; then
    echo "on trunk '$BRANCH' with no tag to diff against — cannot establish a commit range." >&2
    echo "Tag a release, or run from a feature branch." >&2
    exit 65
  fi
else
  for t in "$TRUNK" main master; do
    [[ -z "$t" ]] && continue
    BASE="$(git merge-base HEAD "$t" 2>/dev/null || echo "")"
    [[ -n "$BASE" ]] && break
  done
  if [[ -z "$BASE" ]]; then
    echo "no merge-base with the trunk (tried ${TRUNK:+$TRUNK, }main, master)." >&2
    echo "Refusing to scan full history — it would let unrelated old commits satisfy WIs." >&2
    exit 65
  fi
fi
RANGE="${BASE}..HEAD"

COMMIT_LOG="$(git log --pretty=format:'%s%n%b' "$RANGE" 2>/dev/null || echo "")"

# Test-file WI refs: only from recognized COMMENT lines in the first 30 lines of
# git-TRACKED test files (a WI string buried in code or data must not count).
COMMENT_RE='^[[:space:]]*(//|#|\*|/\*|<!--|--|;)'
TEST_COMMENTS="$(
  git ls-files -z -- '*.test.*' '*.spec.*' '*_test.*' 'test_*' '*/test_*' 2>/dev/null \
    | while IFS= read -r -d '' f; do
        head -n 30 -- "$f" 2>/dev/null | grep -E "$COMMENT_RE"
      done
)"

# Exact, boundary-aware membership — `WI-1.2` must not match `WI-1.20`, `WI-1.2a`,
# `WI-1.2.3`, or `WI-1.2-x`, but must still match before `)`, a space, or a
# sentence-ending `.` (the right boundary rejects a `.`/`-` only when it leads
# into another id character).
wi_present() {
  local wi_esc="${1//./\\.}"
  local re="(^|[^A-Za-z0-9.-])${wi_esc}(\$|[^A-Za-z0-9.-]|[.-](\$|[^A-Za-z0-9]))"
  printf '%s' "$2" | grep -Eq "$re"
}

ok()   { echo "  ✓ $1"; }
miss() { echo "  ✗ $1"; }

LINKED=0
MISSING=()
for wi in "${WIS[@]}"; do
  in_commit=0; in_test=0
  wi_present "$wi" "$COMMIT_LOG"   && in_commit=1
  wi_present "$wi" "$TEST_COMMENTS" && in_test=1
  if (( in_commit + in_test > 0 )); then
    LINKED=$((LINKED + 1))
    src="commit"
    (( in_test == 1 )) && (( in_commit == 0 )) && src="test"
    (( in_test == 1 )) && (( in_commit == 1 )) && src="commit+test"
    ok "$wi linked ($src)"
  else
    MISSING+=("$wi")
    miss "$wi NOT linked (no commit, no test-file comment)"
  fi
done

echo
echo "─────────────────────────────────────────────"
echo "Plan: $PLAN"
echo "WIs found: ${#WIS[@]}    linked: $LINKED    unlinked: ${#MISSING[@]}"
echo "Commit range: $RANGE"

if (( ${#MISSING[@]} > 0 )); then
  echo
  echo "Unlinked WIs (each must appear in a commit message OR a test-file comment):"
  for w in "${MISSING[@]}"; do echo "  • $w"; done
  echo
  echo "Two ways to link a WI:"
  echo "  • Commit message:  feat(scope): wire the parser orchestrator (WI-1.2)"
  echo "  • Test header:     // WI-1.2 — orchestrator dispatch tests   (or  # WI-1.2 — … in #-comment languages)"
  exit 1
fi
exit 0
