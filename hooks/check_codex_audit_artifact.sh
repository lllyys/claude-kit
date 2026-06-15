#!/bin/bash
# PreToolUse hook for the Bash tool.
#
# Blocks `gh pr merge <N>` for source-touching PRs unless the named PR's
# head commit contains a valid Codex audit log at:
#   .claude/codex-audits/<head-branch>-audit.md
#
# Reads PreToolUse JSON from stdin. Exits 0 to allow, 2 to block.

set -euo pipefail

INPUT="$(cat)"

# The hook can only fail open when the enforcement tools themselves are absent.
if ! command -v gh >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    exit 0
fi
if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "[codex-audit-merge-gate] BLOCKED: jq and python3 are required to validate merge audit evidence." >&2
    exit 2
fi

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)"
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"

block() {
    echo "[codex-audit-merge-gate] BLOCKED." >&2
    echo >&2
    printf '%s\n' "$1" >&2
    exit 2
}

# Detect `gh pr merge` AND extract the PR number in one parser pass, so an
# absolute-path gh (`/usr/bin/gh`) can't slip past a surface regex. Compound
# commands are refused: a PR number from a later merge must not license an
# earlier unnumbered one. Output: SKIP | NEEDNUM | BLOCK:<msg> | <pr-number>.
DETECT="$(COMMAND="$COMMAND" python3 - <<'PYEOF'
import os
import re
import shlex
import sys

cmd = os.environ.get("COMMAND", "")

# Shell control operators or substitutions => too ambiguous to validate safely.
compound = bool(re.search(r"[;&|]|\$\(", cmd)) or ("`" in cmd)

try:
    tokens = shlex.split(cmd)
except ValueError:
    print("BLOCK:could not parse the merge command")
    sys.exit(0)

def is_gh(tok):
    return tok.rsplit("/", 1)[-1] == "gh"

invocations = [
    i for i in range(len(tokens) - 2)
    if is_gh(tokens[i]) and tokens[i + 1 : i + 3] == ["pr", "merge"]
]

if not invocations:
    print("SKIP")
    sys.exit(0)
if compound or len(invocations) > 1:
    print("BLOCK:run a single `gh pr merge <N>` as its own command (no chaining or substitutions)")
    sys.exit(0)

for token in tokens[invocations[0] + 3:]:
    if is_gh(token):
        break
    m = re.fullmatch(r"#?([0-9]+)", token) or re.search(r"/pull/([0-9]+)/?$", token)
    if m:
        print(m.group(1))
        sys.exit(0)

print("NEEDNUM")
PYEOF
)"

case "$DETECT" in
    SKIP) exit 0 ;;
    NEEDNUM) block "Use an explicit PR number: gh pr merge <N> [flags]. The audit gate cannot safely infer a PR from the current branch." ;;
    BLOCK:*) block "${DETECT#BLOCK:}" ;;
    *) PR_NUMBER="$DETECT" ;;
esac
if [[ ! "${PR_NUMBER:-}" =~ ^[0-9]+$ ]]; then
    block "Could not determine the PR number for the merge command."
fi

HOOK_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
if ! cd "${HOOK_CWD:-$(pwd)}" 2>/dev/null; then
    block "The Bash tool cwd is unavailable; cannot resolve the repository for PR #$PR_NUMBER."
fi
if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$REPO_ROOT" ]]; then
    block "The merge command is not running inside a Git working tree; cannot validate PR #$PR_NUMBER."
fi
cd "$REPO_ROOT"

if ! PR_JSON="$(gh pr view "$PR_NUMBER" --json headRefName,headRefOid,baseRefName 2>/dev/null)"; then
    block "gh could not resolve PR #$PR_NUMBER. Confirm the PR exists and GitHub is reachable, then retry."
fi

HEAD_BRANCH="$(printf '%s' "$PR_JSON" | jq -r '.headRefName // empty' 2>/dev/null || true)"
HEAD_OID="$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // empty' 2>/dev/null || true)"
BASE_BRANCH="$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // empty' 2>/dev/null || true)"
if [[ -z "$HEAD_BRANCH" || ! "$HEAD_OID" =~ ^[0-9a-fA-F]{40}$ || -z "$BASE_BRANCH" ]]; then
    block "PR #$PR_NUMBER did not return a valid head branch, head commit, and base branch."
fi

# Ensure the exact PR head commit is available locally. GitHub exposes pull
# refs even for fork-originated PRs, where origin/<headRefName> may not exist.
if ! git cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
    if ! git fetch origin "pull/${PR_NUMBER}/head" --quiet 2>/dev/null; then
        block "Could not fetch the head commit for PR #$PR_NUMBER ($HEAD_BRANCH)."
    fi
fi
if ! git cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
    block "The resolved head commit for PR #$PR_NUMBER is unavailable after fetch."
fi

BASE_REF="refs/remotes/origin/$BASE_BRANCH"
if ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
    if ! git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null; then
        block "Could not fetch base branch origin/$BASE_BRANCH for PR #$PR_NUMBER."
    fi
fi
if ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
    block "Base branch origin/$BASE_BRANCH is unavailable after fetch."
fi

# Docs/meta-only PRs do not require a code audit.
# Exempt only by documentation EXTENSION, not by directory: an executable or
# config file under docs/, dev-docs/, or .claude/ (e.g. .claude/hooks/x.sh) is
# source-touching and must still be audited.
DOC_META_RE='\.(md|mdx|txt|rst)$'
if ! CHANGED="$(git diff "${BASE_REF}...${HEAD_OID}" --name-only 2>/dev/null)"; then
    block "Could not compute the changed files for PR #$PR_NUMBER."
fi
if ! printf '%s\n' "$CHANGED" | grep -vE "$DOC_META_RE" | grep -q .; then
    exit 0
fi

SAFE_BRANCH="${HEAD_BRANCH//\//-}"
AUDIT_REL=".claude/codex-audits/${SAFE_BRANCH}-audit.md"
AUDIT_DISPLAY="$REPO_ROOT/$AUDIT_REL"

# Read from the PR head tree, not the working tree. This rejects untracked or
# merely staged evidence and validates the PR named in the merge command.
if ! git cat-file -e "${HEAD_OID}:${AUDIT_REL}" 2>/dev/null; then
    block "PR #$PR_NUMBER branch \`$HEAD_BRANCH\` touches source files but does not contain a tracked audit log at:

  $AUDIT_DISPLAY

Run the Gate 4 audit, write the required frontmatter, commit the log to the PR branch, push it, and retry the merge."
fi
if ! AUDIT_CONTENT="$(git show "${HEAD_OID}:${AUDIT_REL}" 2>/dev/null)"; then
    block "The tracked audit log for PR #$PR_NUMBER could not be read from its head commit."
fi

if ! RESULT="$(printf '%s' "$AUDIT_CONTENT" | AUDIT_BRANCH="$HEAD_BRANCH" python3 -c '
import datetime
import os
import re
import sys

content = sys.stdin.read()
branch = os.environ["AUDIT_BRANCH"]

match = re.match(r"^---[ \t]*\n(.*?)\n---[ \t]*(?:\n|$)", content, re.DOTALL)
if not match:
    print("error: missing or malformed frontmatter")
    raise SystemExit

fields = {}
for line in match.group(1).splitlines():
    if ":" in line:
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip()

if fields.get("branch") != branch:
    print(f"error: branch={fields.get(\"branch\", \"\")!r} does not match PR head branch {branch!r}")
    raise SystemExit

thread_id = fields.get("threadId", "")
if not thread_id or thread_id.startswith("<"):
    print("error: threadId must be a non-empty Codex session id or manual-fallback")
    raise SystemExit

rounds = fields.get("rounds", "")
if not re.fullmatch(r"[1-9][0-9]*", rounds):
    print("error: rounds must be an integer >= 1")
    raise SystemExit

verdict = fields.get("final_verdict", "")
allowed = {"ship-as-is", "follow-up-recommended", "block-recommended"}
if verdict not in allowed:
    print(f"error: final_verdict={verdict!r} must be one of {sorted(allowed)}")
    raise SystemExit
if verdict == "block-recommended":
    print("block: final_verdict=block-recommended")
    raise SystemExit

date = fields.get("date", "")
try:
    datetime.date.fromisoformat(date)
except ValueError:
    print("error: date must be a valid YYYY-MM-DD date")
    raise SystemExit

print("ok")
')"; then
    block "The audit log validator failed unexpectedly for PR #$PR_NUMBER."
fi

case "$RESULT" in
    ok)
        exit 0
        ;;
    block:*)
        block "The audit log at $AUDIT_DISPLAY has final_verdict=block-recommended. Resolve the findings and commit an updated passing audit before merge."
        ;;
    error:*)
        block "The tracked audit log at $AUDIT_DISPLAY has invalid frontmatter.

Reason: ${RESULT#error: }

Required fields:
  branch: $HEAD_BRANCH
  threadId: <Codex session id or manual-fallback>
  rounds: <integer >= 1>
  final_verdict: ship-as-is | follow-up-recommended
  date: YYYY-MM-DD"
        ;;
    *)
        block "The audit log validator returned unexpected output for PR #$PR_NUMBER: $RESULT"
        ;;
esac
