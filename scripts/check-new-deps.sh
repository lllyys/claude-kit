#!/usr/bin/env bash
#
# Slopsquatting / dependency-hallucination gate (rule 60 §4).
#
# Scans a manifest for newly-added dependencies and queries the matching
# package registry for each. Flags any package that's:
#   - non-existent on the registry (likely hallucinated)
#   - created less than $MIN_AGE_DAYS ago (default 30)
#   - has fewer than $MIN_WEEKLY_DL recent downloads (default 1000), where
#     the registry exposes a usage count
#
# Background: USENIX Security 2025 (Spracklen et al.) measured a 5.2–21.7%
# package-hallucination rate in LLM-generated code, with 43% of names
# repeating across runs — actively weaponized as "slopsquatting" supply-chain
# attacks. Pinning lockfiles isn't enough; new package additions need eyes.
#
# Stack-agnostic: detects the ecosystem from the manifests present and probes
# the right registry. Supported:
#   package.json                       -> npm        (registry.npmjs.org)
#   pyproject.toml / requirements.txt  -> PyPI       (pypi.org)
#   Cargo.toml                         -> crates.io  (crates.io/api)
#   go.mod                             -> Go modules (proxy.golang.org)
#
# Usage:
#   bash scripts/check-new-deps.sh [base-ref]
# Default base-ref is origin/main -> main -> previous tag.
#
# Requires: git, curl, jq. (jq replaces the npm-CLI + node dependency of the
# original so non-Node projects can run the gate. If jq is missing, the gate
# fails open with a clear message — install jq in CI to enforce it.)
#
# Exit codes:
#   0  no new deps, OR every new dep passes the flag thresholds (or fail-open)
#   1  one or more new deps flagged for human review (CI fails)
#  64  bad invocation

set -uo pipefail
cd "$(dirname "$0")/.."

MIN_AGE_DAYS="${MIN_AGE_DAYS:-30}"
MIN_WEEKLY_DL="${MIN_WEEKLY_DL:-1000}"
UA="claude-coding-kit-check-new-deps/1.0 (+https://github.com/lllyys/claude-coding-kit)"
BASE="${1:-}"

if ! command -v jq >/dev/null 2>&1; then
  echo "check-new-deps: jq not found — install jq to enforce the dependency gate. Skipping (fail-open)." >&2
  exit 0
fi

# Resolve the base ref to diff against.
if [[ -z "$BASE" ]]; then
  if git rev-parse --verify origin/main >/dev/null 2>&1; then BASE="origin/main"
  elif git rev-parse --verify main >/dev/null 2>&1; then BASE="main"
  else BASE=$(git describe --tags --abbrev=0 2>/dev/null || echo ""); fi
fi
if [[ -z "$BASE" ]]; then
  echo "could not determine base ref; pass one explicitly"
  exit 64
fi

# --- HTTP helper: sets HTTP_BODY + HTTP_CODE (000 on network error) ----------
HTTP_BODY=""; HTTP_CODE=""
http_get() {
  local url="$1" resp
  resp=$(curl -sSL --max-time 15 -A "$UA" -w $'\n%{http_code}' "$url" 2>/dev/null) || {
    HTTP_CODE="000"; HTTP_BODY=""; return 0; }
  HTTP_CODE="${resp##*$'\n'}"
  HTTP_BODY="${resp%$'\n'*}"
}

# --- date helper: ISO-8601 -> epoch (BSD `date -j` then GNU `date -d`) --------
iso_to_epoch() {
  local iso="${1%.*}"   # drop fractional seconds
  iso="${iso%Z}"        # drop trailing Z
  date -j -u -f "%Y-%m-%dT%H:%M:%S" "$iso" +%s 2>/dev/null \
    || date -d "$1" +%s 2>/dev/null || echo 0
}

# --- per-ecosystem new-dependency extractors (added diff lines only) ---------
extract_npm() {  # stdin: diff
  grep -E '^\+[[:space:]]+"(@[^/"]+/[^"]+|[^"@][^"]*)"[[:space:]]*:' \
    | sed -E 's/^\+[[:space:]]+"([^"]+)".*/\1/' \
    | grep -vE '^(name|version|description|scripts|dependencies|devDependencies|peerDependencies|optionalDependencies|engines|exports|bin|repository|keywords|author|license|type|main|module|types|files|publishConfig|overrides|resolutions|workspaces|packageManager|private|homepage|bugs|funding|browserslist|sideEffects)$' \
    | sort -u
}
extract_pypi() {  # stdin: diff (pyproject.toml or requirements.txt)
  grep -E '^\+' | sed -E 's/^\+//; s/^[[:space:]]*//; s/^"//' \
    | grep -vE '^\[' \
    | grep -E '^[A-Za-z0-9]' \
    | sed -E 's/^([A-Za-z0-9][A-Za-z0-9._-]*).*/\1/' \
    | grep -vEi '^(python|dependencies|optional-dependencies|dev-dependencies|name|version|description|requires-python|readme|license|authors|maintainers|classifiers|keywords|urls|homepage|repository|scripts|build-backend|requires|packages|include|exclude)$' \
    | sort -u
}
extract_cargo() {  # stdin: diff (Cargo.toml)
  grep -E '^\+' | sed -E 's/^\+//; s/^[[:space:]]*//' \
    | grep -vE '^\[' \
    | grep -E '^[A-Za-z0-9_-]+[[:space:]]*=' \
    | sed -E 's/^([A-Za-z0-9_-]+).*/\1/' \
    | grep -vEi '^(name|version|edition|authors|description|license|license-file|repository|homepage|documentation|readme|keywords|categories|workspace|rust-version|publish|default-run|build|links|exclude|include|resolver)$' \
    | sort -u
}
extract_go() {  # stdin: diff (go.mod)
  grep -E '^\+' | sed -E 's/^\+//; s/^[[:space:]]*//' \
    | grep -E '^[a-z0-9][^[:space:]]*/[^[:space:]]+[[:space:]]+v[0-9]' \
    | sed -E 's/^([^[:space:]]+)[[:space:]]+.*/\1/' \
    | grep -vE '^(module|go|require|replace|exclude|toolchain)$' \
    | sort -u
}

# --- per-registry probe: echoes "status<TAB>created_iso<TAB>count" -----------
# status: ok | notfound | error ; count may be "?" when unavailable.
probe_npm() {
  local pkg enc; pkg="$1"; enc="${pkg//\//%2F}"
  http_get "https://registry.npmjs.org/${enc}"
  case "$HTTP_CODE" in
    200) : ;; 404) echo $'notfound\t\t?'; return ;; *) echo $'error\t\t?'; return ;;
  esac
  local created count
  created=$(printf '%s' "$HTTP_BODY" | jq -r '.time.created // ""' 2>/dev/null)
  http_get "https://api.npmjs.org/downloads/point/last-week/${enc}"
  count=$(printf '%s' "$HTTP_BODY" | jq -r '.downloads // "?"' 2>/dev/null); [[ -z "$count" ]] && count="?"
  printf 'ok\t%s\t%s\n' "$created" "$count"
}
probe_pypi() {
  local pkg; pkg="$1"
  http_get "https://pypi.org/pypi/${pkg}/json"
  case "$HTTP_CODE" in
    200) : ;; 404) echo $'notfound\t\t?'; return ;; *) echo $'error\t\t?'; return ;;
  esac
  # earliest upload across all releases ≈ creation date; PyPI has no public
  # download API, so usage count is unknown.
  local created
  created=$(printf '%s' "$HTTP_BODY" | jq -r '[.releases[][]?.upload_time_iso_8601] | map(select(. != null)) | sort | .[0] // ""' 2>/dev/null)
  printf 'ok\t%s\t%s\n' "$created" "?"
}
probe_cargo() {
  local pkg; pkg="$1"
  http_get "https://crates.io/api/v1/crates/${pkg}"
  case "$HTTP_CODE" in
    200) : ;; 404) echo $'notfound\t\t?'; return ;; *) echo $'error\t\t?'; return ;;
  esac
  local created count
  created=$(printf '%s' "$HTTP_BODY" | jq -r '.crate.created_at // ""' 2>/dev/null)
  # recent_downloads is a ~90-day count; used as a "negligible usage" signal.
  count=$(printf '%s' "$HTTP_BODY" | jq -r '.crate.recent_downloads // .crate.downloads // "?"' 2>/dev/null); [[ -z "$count" ]] && count="?"
  printf 'ok\t%s\t%s\n' "$created" "$count"
}
probe_go() {
  local mod; mod="$1"
  # Go module proxy escapes uppercase as !<lower>; lowercase the path for the
  # escape, which is correct for the common all-lowercase module paths.
  local esc; esc=$(printf '%s' "$mod" | sed -E 's/([A-Z])/!\L\1/g')
  http_get "https://proxy.golang.org/${esc}/@latest"
  case "$HTTP_CODE" in
    200) : ;; 404|410) echo $'notfound\t\t?'; return ;; *) echo $'error\t\t?'; return ;;
  esac
  # @latest gives the latest version's publish time (proxy has no module
  # creation date); used as an age proxy. No usage count is available.
  local created
  created=$(printf '%s' "$HTTP_BODY" | jq -r '.Time // ""' 2>/dev/null)
  printf 'ok\t%s\t%s\n' "$created" "?"
}

# --- detect ecosystems present and changed, collect (ecosystem, deps) --------
NOW_EPOCH=$(date +%s)
SECS_PER_DAY=86400
FLAGGED=0
ANY_ECO=0

inspect() {  # ecosystem  manifest  registry-label
  local eco="$1" manifest="$2" label="$3"
  [[ -f "$manifest" ]] || return 0
  local diff; diff=$(git diff "$BASE" -- "$manifest" 2>/dev/null || true)
  [[ -z "$diff" ]] && return 0
  ANY_ECO=1
  local pkgs
  pkgs=$(printf '%s\n' "$diff" | "extract_${eco}")
  [[ -z "$pkgs" ]] && { echo "[$label] $manifest changed but no new dependency lines detected."; return 0; }

  echo "[$label] inspecting newly-added dependencies in $manifest (vs $BASE):"
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    local out status created count
    out=$("probe_${eco}" "$pkg")
    status=$(printf '%s' "$out" | cut -f1)
    created=$(printf '%s' "$out" | cut -f2)
    count=$(printf '%s' "$out" | cut -f3)

    if [[ "$status" == "notfound" ]]; then
      echo "  ✗ $pkg — NOT FOUND on $label (likely hallucinated)"
      FLAGGED=$((FLAGGED+1)); continue
    fi
    if [[ "$status" == "error" ]]; then
      echo "  ? $pkg — registry probe failed (network?) — not flagged (fail-open)"
      continue
    fi

    local age="?"
    if [[ -n "$created" ]]; then
      local ce; ce=$(iso_to_epoch "$created")
      (( ce > 0 )) && age=$(( (NOW_EPOCH - ce) / SECS_PER_DAY ))
    fi

    local reasons=()
    [[ "$age"   != "?" ]] && (( age   < MIN_AGE_DAYS ))   && reasons+=("created ${age}d ago (<${MIN_AGE_DAYS})")
    [[ "$count" != "?" ]] && (( count < MIN_WEEKLY_DL ))  && reasons+=("${count} recent dl (<${MIN_WEEKLY_DL})")

    if (( ${#reasons[@]} > 0 )); then
      local join; join=$(IFS=', '; echo "${reasons[*]}")
      echo "  ⚠ $pkg — flagged: $join  (age=${age}d, dl=${count})"
      FLAGGED=$((FLAGGED+1))
    else
      echo "  ✓ $pkg — age=${age}d, dl=${count}"
    fi
  done <<< "$pkgs"
  echo
}

inspect npm   package.json     npm
inspect pypi  pyproject.toml   PyPI
inspect pypi  requirements.txt PyPI
inspect cargo Cargo.toml       crates.io
inspect go    go.mod           Go

if (( ANY_ECO == 0 )); then
  echo "no dependency-manifest changes vs $BASE — clean"
  exit 0
fi

if (( FLAGGED > 0 )); then
  echo "$FLAGGED new dependency(ies) flagged for review."
  echo "If a flag is a false positive, document why in the PR description."
  echo "If a flag is real, treat it as a possible LLM hallucination or slopsquat."
  exit 1
fi
echo "All new dependencies pass the slopsquatting heuristics."
exit 0
