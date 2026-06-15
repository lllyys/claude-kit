#!/usr/bin/env bash
#
# Slopsquatting / dependency-hallucination gate (rule 60 §4).
#
# Scans every CHANGED dependency manifest (monorepo-aware) for newly-added
# dependencies and probes the matching registry. Flags any package that's:
#   - non-existent on the registry (likely hallucinated)
#   - created less than $MIN_AGE_DAYS ago (default 30), where the registry
#     exposes a creation date
#   - has fewer than $MIN_WEEKLY_DL recent downloads (default 1000), where the
#     registry exposes a usage count
#   - has a syntactically invalid / hostile name (rejected before any probe)
#
# Background: USENIX Security 2025 (Spracklen et al.) measured a 5.2–21.7%
# package-hallucination rate in LLM-generated code, with 43% of names repeating
# across runs — weaponized as "slopsquatting" supply-chain attacks.
#
# SECURITY: this parses UNTRUSTED input (git diffs, registry JSON, package names
# from a possibly-malicious PR manifest). Every value that reaches Bash
# arithmetic is integer-validated first — `(( ))` evaluates arithmetic strings
# (including command substitution), so an unvalidated registry value would be an
# injection vector. Package/module names are charset-validated before entering a
# URL, and curl is https-only, redirect-free, and size/time-capped.
#
# FAIL-CLOSED: a missing tool or a registry/network error yields an
# "indeterminate" exit (3), never a silent pass. Set ALLOW_INDETERMINATE=1 to
# downgrade indeterminate outcomes to a non-failing warning (e.g. flaky CI).
#
# Supported manifests:
#   package.json                       -> npm        (registry.npmjs.org)
#   requirements.txt / pyproject.toml  -> PyPI       (pypi.org)
#   Cargo.toml                         -> crates.io  (crates.io/api)
#   go.mod                             -> Go modules (proxy.golang.org)
#
# Heuristic limits (documented, not silent):
#   - pyproject.toml / Cargo.toml are TOML; parsed with python3 `tomllib`
#     (>=3.11) when available — this resolves Cargo `package = "..."` renames and
#     multi-line arrays. Without tomllib, a coarse line heuristic is used.
#   - go.mod uses `go mod edit -json` when `go` is on PATH (handles block,
#     single-line, and replace directives); otherwise a line parser.
#   - requirements.txt `-r other.txt` includes are NOT followed.
#   - PyPI exposes no public download count and the Go proxy exposes no module
#     creation date, so those axes are reported unknown rather than guessed.
#
# Requires: git, curl, jq.
#
# Usage:   bash scripts/check-new-deps.sh [base-ref]
# Exit:    0 clean | 1 flagged | 3 indeterminate (tool/registry failure) | 64 bad invocation | 65 git state

set -uo pipefail
cd "$(dirname "$0")/.."

MIN_AGE_DAYS="${MIN_AGE_DAYS:-30}"
MIN_WEEKLY_DL="${MIN_WEEKLY_DL:-1000}"
ALLOW_INDETERMINATE="${ALLOW_INDETERMINATE:-0}"
UA="claude-coding-kit-check-new-deps/1.1 (+https://github.com/lllyys/claude-coding-kit)"
BASE="${1:-}"

is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

# Thresholds feed Bash arithmetic — reject anything non-integer up front.
is_uint "$MIN_AGE_DAYS"  || { echo "MIN_AGE_DAYS must be a non-negative integer"  >&2; exit 64; }
is_uint "$MIN_WEEKLY_DL" || { echo "MIN_WEEKLY_DL must be a non-negative integer" >&2; exit 64; }

INDETERMINATE=0
note_indet() { echo "  ? $1" >&2; INDETERMINATE=$((INDETERMINATE + 1)); }

# Fail closed on missing prerequisites.
missing=""
for t in git curl jq; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
if [[ -n "$missing" ]]; then
  if [[ "$ALLOW_INDETERMINATE" == "1" ]]; then
    echo "check-new-deps: missing tools:$missing — ALLOW_INDETERMINATE=1, passing without checks." >&2
    exit 0
  fi
  echo "check-new-deps: missing required tools:$missing — cannot run the gate (exit 3)." >&2
  echo "  Install them, or set ALLOW_INDETERMINATE=1 to bypass." >&2
  exit 3
fi

# Resolve + VALIDATE the base ref (must be a real commit).
if [[ -z "$BASE" ]]; then
  if   git rev-parse --verify origin/main >/dev/null 2>&1; then BASE="origin/main"
  elif git rev-parse --verify main        >/dev/null 2>&1; then BASE="main"
  else BASE="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"; fi
fi
if [[ -z "$BASE" ]] || ! git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1; then
  echo "could not resolve a valid base ref (got '${BASE:-<none>}'); pass one explicitly" >&2
  exit 64
fi

# ── HTTP: https-only, no redirect-follow (SSRF), size + time capped ──────────
HTTP_BODY=""; HTTP_CODE=""
http_get() {
  local resp
  resp="$(curl -sS --max-time 15 --max-filesize 5000000 --proto '=https' \
            -A "$UA" -w $'\n%{http_code}' -- "$1" 2>/dev/null)" \
    || { HTTP_CODE="000"; HTTP_BODY=""; return 0; }
  HTTP_CODE="${resp##*$'\n'}"
  HTTP_BODY="${resp%$'\n'*}"
}

# Validated jq: nonzero (and empty) on parse error or JSON null.
jqv() { printf '%s' "$1" | jq -e -r "$2" 2>/dev/null; }

# ISO-8601 -> epoch, portable (BSD `date -j` then GNU `date -d`); 0 on failure.
iso_to_epoch() {
  local iso="$1"
  iso="${iso%%.*}"           # drop fractional seconds
  iso="${iso%%+*}"           # drop +HH:MM offset
  iso="${iso%Z}"             # drop trailing Z
  date -j -u -f "%Y-%m-%dT%H:%M:%S" "$iso" +%s 2>/dev/null \
    || date -u -d "$1" +%s 2>/dev/null || echo 0
}

# Charset validation per ecosystem — a name failing this is itself a red flag.
valid_name() {
  case "$1" in
    npm)   [[ "$2" =~ ^@?[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?$ ]] ;;
    pypi)  [[ "$2" =~ ^[A-Za-z0-9._-]+$ ]] ;;
    cargo) [[ "$2" =~ ^[A-Za-z0-9_-]+$ ]] ;;
    go)    [[ "$2" =~ ^[A-Za-z0-9._~/-]+$ ]] ;;
    *) return 1 ;;
  esac
}

# Go module-proxy escape (Uppercase X -> !x), portable (no GNU sed \L).
go_escape() {
  local s="$1" out="" i c
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    if [[ "$c" =~ [A-Z] ]]; then out+="!$(printf '%s' "$c" | tr 'A-Z' 'a-z')"; else out+="$c"; fi
  done
  printf '%s' "$out"
}

old_blob() { git show "${BASE}:$1" 2>/dev/null || true; }
new_blob() { [[ -f "$1" ]] && cat -- "$1" 2>/dev/null || true; }

# Does the NEW manifest parse? Used to FAIL CLOSED: an empty extraction from an
# UNPARSEABLE manifest must not be reported as "no new dependencies". Returns 0
# when it parses (or cannot be structurally validated because the tool is absent).
manifest_parses() {  # path content
  case "$(basename -- "$1")" in
    package.json)
      printf '%s' "$2" | jq -e . >/dev/null 2>&1 ;;
    pyproject.toml|Cargo.toml)
      command -v python3 >/dev/null 2>&1 || return 0   # no tomllib -> heuristic, can't validate
      printf '%s' "$2" | python3 -c '
import sys
try:
    import tomllib
except ModuleNotFoundError:
    sys.exit(0)
try:
    tomllib.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
' ;;
    go.mod)
      command -v go >/dev/null 2>&1 || return 0   # regex fallback, can't validate
      local tmp rc; tmp="$(mktemp)"; printf '%s' "$2" > "$tmp"
      go mod edit -json "$tmp" >/dev/null 2>&1; rc=$?; rm -f "$tmp"; return "$rc" ;;
    *) return 0 ;;   # requirements.txt etc. — line-based, nothing to fail to parse
  esac
}

# ── New-dependency extractors: print probe-names present in NEW but not OLD ──
npm_keys() {
  printf '%s' "$1" | jq -r \
    '[.dependencies,.devDependencies,.optionalDependencies,.peerDependencies]
     | map(select(type=="object")|keys[]) | .[]?' 2>/dev/null | sort -u
}
extract_npm() { comm -13 <(npm_keys "$1") <(npm_keys "$2"); }

req_names() {
  printf '%s\n' "$1" | while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ "$line" =~ ^[A-Za-z0-9] ]] || continue   # skip blanks + -r/-e/--option lines
    printf '%s\n' "$line" | sed -E 's/^([A-Za-z0-9._-]+).*/\1/'
  done | sort -u
}
extract_pypi_req() { comm -13 <(req_names "$1") <(req_names "$2"); }

# TOML (cargo / pyproject) via python tomllib; returns nonzero -> caller falls
# back to the heuristic below.
toml_added() {
  command -v python3 >/dev/null 2>&1 || return 2
  ECO="$1" OLD="$2" NEW="$3" python3 - <<'PY'
import os, re, sys
try:
    import tomllib
except Exception:
    sys.exit(2)
eco = os.environ["ECO"]
def parse(s):
    try: return tomllib.loads(s)
    except Exception: return None
old, new = parse(os.environ["OLD"]), parse(os.environ["NEW"])
if new is None:           # can't parse the new manifest -> signal fallback
    sys.exit(2)
old = old or {}
def pep508(spec):
    m = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9._-]*)", spec or "")
    return m.group(1) if m else ""
def names(data):
    out = set()
    if not data: return out
    if eco == "cargo":
        for sec in ("dependencies", "dev-dependencies", "build-dependencies"):
            for k, v in (data.get(sec, {}) or {}).items():
                out.add(v.get("package", k) if isinstance(v, dict) else k)
    else:  # pypi
        proj = data.get("project", {}) or {}
        for spec in (proj.get("dependencies", []) or []):
            out.add(pep508(spec))
        for arr in (proj.get("optional-dependencies", {}) or {}).values():
            for spec in (arr or []): out.add(pep508(spec))
        poetry = ((data.get("tool", {}) or {}).get("poetry", {}) or {}).get("dependencies", {}) or {}
        for k in poetry:
            if k.lower() != "python": out.add(k)
    return out
print("\n".join(sorted(names(new) - names(old) - {""})))
PY
}
_cargo_heuristic() {
  _ck() { printf '%s\n' "$1" | grep -E '^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=' \
    | sed -E 's/^[[:space:]]*([A-Za-z0-9_-]+).*/\1/' \
    | grep -vEi '^(name|version|edition|authors|description|license|license-file|repository|homepage|documentation|readme|keywords|categories|workspace|rust-version|publish|default-run|build|links|exclude|include|resolver)$' | sort -u; }
  comm -13 <(_ck "$1") <(_ck "$2")
}
_pypi_heuristic() {
  _pk() { printf '%s\n' "$1" | grep -oE '"[A-Za-z0-9][A-Za-z0-9._-]*' | tr -d '"' | sort -u; }
  comm -13 <(_pk "$1") <(_pk "$2")
}

go_requires() {
  if command -v go >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp)"; printf '%s' "$1" > "$tmp"
    go mod edit -json "$tmp" 2>/dev/null | jq -r '.Require[]?.Path' 2>/dev/null | sort -u
    rm -f "$tmp"
  else
    printf '%s\n' "$1" | sed -E 's/^[[:space:]]*//; s/^require[[:space:]]+//' \
      | grep -E '^[A-Za-z0-9][^[:space:]]*/[^[:space:]]+[[:space:]]+v[0-9]' \
      | sed -E 's/^([^[:space:]]+).*/\1/' | sort -u
  fi
}
extract_go() { comm -13 <(go_requires "$1") <(go_requires "$2"); }

# ── Probe + judge one package ────────────────────────────────────────────────
NOW="$(date +%s)"; DAY=86400; FLAGGED=0
probe_and_judge() {
  local eco="$1" label="$2" name="$3"
  if ! valid_name "$eco" "$name"; then
    echo "  ✗ $name — invalid/suspicious $label name (rejected before probe)"
    FLAGGED=$((FLAGGED + 1)); return
  fi
  local body created count="?"
  case "$eco" in
    npm)   http_get "https://registry.npmjs.org/${name//\//%2F}" ;;
    pypi)  http_get "https://pypi.org/pypi/${name}/json" ;;
    cargo) http_get "https://crates.io/api/v1/crates/${name}" ;;
    go)    http_get "https://proxy.golang.org/$(go_escape "$name")/@latest" ;;
  esac
  body="$HTTP_BODY"
  case "$HTTP_CODE" in
    200) ;;
    404|410) echo "  ✗ $name — NOT FOUND on $label (likely hallucinated)"; FLAGGED=$((FLAGGED + 1)); return ;;
    *) note_indet "$name — $label probe inconclusive (HTTP $HTTP_CODE)"
       echo "  ? $name — $label probe inconclusive (HTTP $HTTP_CODE)"; return ;;
  esac
  case "$eco" in
    npm)   created="$(jqv "$body" '.time.created' || true)"
           http_get "https://api.npmjs.org/downloads/point/last-week/${name//\//%2F}"
           [[ "$HTTP_CODE" == "200" ]] && count="$(jqv "$HTTP_BODY" '.downloads' || echo '?')" ;;
    pypi)  created="$(jqv "$body" '[.releases[][]?.upload_time_iso_8601]|map(select(.!=null))|sort|.[0]' || true)" ;;
    cargo) created="$(jqv "$body" '.crate.created_at' || true)"
           count="$(jqv "$body" '.crate.recent_downloads // .crate.downloads' || echo '?')" ;;
    go)    created="" ;;   # proxy @latest time != module creation; Go age unsupported
  esac
  is_uint "$count" || count="?"
  local age="?"
  if [[ -n "$created" ]]; then
    local ce; ce="$(iso_to_epoch "$created")"
    is_uint "$ce" && (( ce > 0 )) && age=$(( (NOW - ce) / DAY ))
  fi
  local reasons=()
  [[ "$age"   != "?" ]] && is_uint "$age"   && (( age   < MIN_AGE_DAYS  )) && reasons+=("created ${age}d ago (<${MIN_AGE_DAYS})")
  [[ "$count" != "?" ]] && is_uint "$count" && (( count < MIN_WEEKLY_DL )) && reasons+=("${count} recent dl (<${MIN_WEEKLY_DL})")
  if (( ${#reasons[@]} > 0 )); then
    local j; j="$(IFS=', '; echo "${reasons[*]}")"
    echo "  ⚠ $name — flagged: $j  (age=${age}, dl=${count})"; FLAGGED=$((FLAGGED + 1))
  else
    echo "  ✓ $name — age=${age}, dl=${count}"
  fi
}

# ── Discover changed manifests (monorepo-aware) and inspect each ─────────────
ANY=0
process_manifest() {
  local f="$1" eco label names old new
  case "$(basename -- "$f")" in
    package.json)     eco=npm;  label=npm ;;
    requirements.txt) eco=pypi; label=PyPI ;;
    pyproject.toml)   eco=pypi; label=PyPI ;;
    Cargo.toml)       eco=cargo; label=crates.io ;;
    go.mod)           eco=go;   label=Go ;;
    *) return 0 ;;
  esac
  ANY=1
  old="$(old_blob "$f")"; new="$(new_blob "$f")"
  if [[ -n "$new" ]] && ! manifest_parses "$f" "$new"; then
    note_indet "$f — new manifest does not parse (malformed?); not inspected"
    echo "[$label] $f changed — UNPARSEABLE, fail-closed (indeterminate)."
    return 0
  fi
  case "$(basename -- "$f")" in
    package.json)     names="$(extract_npm "$old" "$new")" ;;
    requirements.txt) names="$(extract_pypi_req "$old" "$new")" ;;
    pyproject.toml)   names="$(toml_added pypi  "$old" "$new")" || names="$(_pypi_heuristic "$old" "$new")" ;;
    Cargo.toml)       names="$(toml_added cargo "$old" "$new")" || names="$(_cargo_heuristic "$old" "$new")" ;;
    go.mod)           names="$(extract_go "$old" "$new")" ;;
  esac
  if [[ -z "$names" ]]; then
    echo "[$label] $f changed — no new dependencies detected."
    return 0
  fi
  echo "[$label] new dependencies in $f (vs $BASE):"
  while IFS= read -r n; do [[ -n "$n" ]] && probe_and_judge "$eco" "$label" "$n"; done <<< "$names"
  echo
}

if ! CHANGED_LIST="$(git diff "$BASE" --name-only 2>/dev/null)"; then
  echo "could not diff against $BASE (git error) — result indeterminate." >&2
  [[ "$ALLOW_INDETERMINATE" == "1" ]] && exit 0
  exit 3
fi
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$(basename -- "$f")" in
    package.json|requirements.txt|pyproject.toml|Cargo.toml|go.mod) process_manifest "$f" ;;
  esac
done <<< "$CHANGED_LIST"

# ── Verdict ──────────────────────────────────────────────────────────────────
if (( ANY == 0 )); then
  echo "no dependency-manifest changes vs $BASE — clean"
  exit 0
fi
if (( FLAGGED > 0 )); then
  echo "$FLAGGED new dependency(ies) flagged for review."
  echo "Document false positives in the PR; treat real flags as possible hallucination/slopsquat."
  exit 1
fi
if (( INDETERMINATE > 0 )); then
  if [[ "$ALLOW_INDETERMINATE" == "1" ]]; then
    echo "$INDETERMINATE probe(s) inconclusive; ALLOW_INDETERMINATE=1 — not failing."
    exit 0
  fi
  echo "$INDETERMINATE probe(s) inconclusive (network/registry error) — result indeterminate."
  echo "Re-run, or set ALLOW_INDETERMINATE=1 to treat inconclusive probes as passing."
  exit 3
fi
echo "All new dependencies pass the slopsquatting heuristics."
exit 0
