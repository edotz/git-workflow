#!/usr/bin/env bash
# Purpose: Run bin/modules/git/rules-sync.sh against stub docker, gh and curl commands and check that it names what still
#          guards a managed branch without being managed: a foreign ruleset with its id, the classic branch protection
#          with its required checks, a failed read as a failed read and never as "not protected", and that nothing is
#          deleted or written for it.
# Usage: bash tests/git-rules/foreign.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per check, ok or FAIL
# Exit codes: 0 all checks hold, 1 a check failed
set -euo pipefail

ROOT="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
source "${BU_ROOT:?run through the framework shell or set BU_ROOT}/lib/core.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STUBS="${WORK}/stubs"
mkdir -p "$STUBS"

failures=0
STUB_DIR=""
OUT=""
RC=0

# ============================================
# Stubs: the tool image runs docker, the host runs gh and curl
# ============================================

cat >"${STUBS}/docker" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  image) exit 0 ;;
  run)
    shift
    while [[ $# -gt 0 && "$1" != edotz-git-workflow-tools:* ]]; do shift; done
    shift
    exec "$@"
    ;;
esac
exit 1
STUB

cat >"${STUBS}/curl" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf '{"token":"stub-installation-token"}\n200'
STUB

# The rulesets are files rulesets/<id>.json; the classic protection of a branch is the file protection/<branch>: absent
# answers 404, the word 403 answers 403, any other content is the JSON answer.
cat >"${STUBS}/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
dir="${STUB_DIR}"
if [[ "${1:-}" == "auth" ]]; then
  echo "stub-developer-token"
  exit 0
fi
shift
method="GET"
endpoint=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method | -X) method="$2"; shift 2 ;;
    -H | --header | --input) shift 2 ;;
    -*) shift ;;
    *) endpoint="$1"; shift ;;
  esac
done
path="${endpoint%%\?*}"
echo "gh ${method} ${path}" >>"${dir}/calls.log"
shopt -s nullglob
case "${method} ${path}" in
  "GET repos/acme/widgets/rulesets")
    files=("${dir}"/rulesets/*.json)
    if [[ ${#files[@]} -eq 0 ]]; then echo '[]'; else jq -c -s '[.[] | {id, name}]' "${files[@]}"; fi
    ;;
  "GET repos/acme/widgets/rulesets/"*)
    cat "${dir}/rulesets/${path##*/}.json"
    ;;
  "GET repos/acme/widgets/branches/"*"/protection")
    branch="${path#repos/acme/widgets/branches/}"
    branch="${branch%/protection}"
    file="${dir}/protection/${branch}"
    if [[ ! -f "$file" ]]; then
      echo "gh: Branch not protected (HTTP 404)" >&2
      exit 1
    fi
    if [[ "$(<"$file")" == "403" ]]; then
      echo "gh: Resource not accessible by integration (HTTP 403)" >&2
      exit 1
    fi
    cat "$file"
    ;;
  "POST repos/acme/widgets/rulesets")
    body="$(cat)"
    id=$(($(<"${dir}/counter") + 1))
    echo "$id" >"${dir}/counter"
    jq -c --argjson id "$id" '. + {id: $id}' <<<"$body" >"${dir}/rulesets/${id}.json"
    echo "{\"id\":${id}}"
    ;;
  *)
    exit 1
    ;;
esac
STUB
chmod +x "${STUBS}/docker" "${STUBS}/curl" "${STUBS}/gh"

# ============================================
# Helpers
# ============================================

# Create a throwaway project: a git repository whose origin is acme/widgets and an empty .agentic-os directory.
make_project() {
  mkdir -p "$1/.agentic-os"
  git -C "$1" init -q
  git -C "$1" remote add origin git@github.com:acme/widgets.git
  return 0
}

# Start a fresh stub state: no rulesets, no classic protection and an empty call log. Sets STUB_DIR.
new_state() {
  STUB_DIR="$(mktemp -d -p "$WORK")"
  mkdir -p "${STUB_DIR}/rulesets" "${STUB_DIR}/protection"
  echo 100 >"${STUB_DIR}/counter"
  : >"${STUB_DIR}/calls.log"
  return 0
}

# Put a ruleset into the stub state.
# Args: $1 - id  $2 - name  $3 - enforcement  $4 - include patterns as a JSON list
add_ruleset() {
  jq -c -n --argjson id "$1" --arg name "$2" --arg enf "$3" --argjson inc "$4" \
    '{id: $id, name: $name, target: "branch", enforcement: $enf, conditions: {ref_name: {include: $inc, exclude: []}}, rules: []}' \
    >"${STUB_DIR}/rulesets/$1.json"
  return 0
}

# Run rules-sync in the project with a clean environment, the stubs first on PATH. Sets OUT and RC.
# Args: $1.. - arguments of rules-sync
run_sync() {
  RC=0
  OUT="$(cd "$PROJECT" && env -i HOME="$WORK" PATH="${STUBS}:${PATH}" BU_ROOT="$BU_ROOT" PLUGIN_ROOT="$ROOT" \
    STUB_DIR="$STUB_DIR" GIT_WORKFLOW_RELEASE_BRANCH=release GIT_WORKFLOW_APP_ID=4711 \
    bash "${ROOT}/bin/modules/git/rules-sync.sh" "$@" 2>&1)" || RC=$?
  return 0
}

# Record one check: ok when the status is 0.
verdict() {
  if [[ "$2" -eq 0 ]]; then
    print_line "ok   $1"
  else
    print_line "FAIL $1"
    failures=$((failures + 1))
  fi
  return 0
}

# Pass when OUT holds the text.
expect_out() {
  local status=1
  if [[ "$OUT" == *"$2"* ]]; then status=0; fi
  verdict "$1" "$status"
  return 0
}

# Pass when OUT does not hold the text.
expect_not_out() {
  local status=0
  if [[ "$OUT" == *"$2"* ]]; then status=1; fi
  verdict "$1" "$status"
  return 0
}

# Pass when the exit code of the run is the number.
expect_rc() {
  local status=1
  if [[ "$RC" -eq "$2" ]]; then status=0; fi
  verdict "$1" "$status"
  return 0
}

# Pass when the call log holds no call that starts with the method.
expect_no_call() {
  local status=0
  if grep -q "^gh $2 " "${STUB_DIR}/calls.log"; then status=1; fi
  verdict "$1" "$status"
  return 0
}

PROJECT="${WORK}/project"
make_project "$PROJECT"

# ============================================
# Checks
# ============================================

new_state
add_ruleset 7 old-protection active '["~DEFAULT_BRANCH"]'
add_ruleset 8 retired-rule disabled '["refs/heads/master"]'
add_ruleset 9 elsewhere active '["refs/heads/feature/*"]'
run_sync --dry-run
expect_rc "the dry run succeeds with a foreign ruleset present" 0
expect_out "a foreign ruleset on the default branch is named with its id" "foreign ruleset 7 old-protection covers master"
expect_not_out "a disabled ruleset and one on other branches are not named" "foreign ruleset 8"
expect_not_out "a ruleset on other branches is not named" "foreign ruleset 9"
expect_no_call "a foreign ruleset is never deleted" "DELETE"

new_state
add_ruleset 3 master active '["refs/heads/master"]'
run_sync --dry-run
expect_not_out "a managed ruleset is not named as foreign" "foreign ruleset 3"

new_state
printf '{"required_status_checks":{"contexts":["commit-lint","php-cs-fixer"]}}\n' >"${STUB_DIR}/protection/master"
run_sync --dry-run
expect_out "classic protection is named with its required checks" "classic protection covers master"
expect_out "the required checks are listed" "commit-lint, php-cs-fixer"

new_state
echo 403 >"${STUB_DIR}/protection/master"
run_sync --dry-run
expect_out "a failed read of the classic protection is named as a failed read" "classic protection of master — failed read"
expect_not_out "a failed read is not reported as protected" "classic protection covers master"

new_state
run_sync --dry-run
expect_not_out "a 404 means not protected and prints nothing" "classic protection"

new_state
add_ruleset 7 old-protection active '["~DEFAULT_BRANCH"]'
printf '{"required_status_checks":{"contexts":["check"]}}\n' >"${STUB_DIR}/protection/master"
run_sync --apply
expect_out "the apply names the foreign ruleset too" "foreign ruleset 7 old-protection covers master"
expect_out "the apply names the classic protection too" "classic protection covers master"
expect_no_call "the apply deletes nothing" "DELETE"
expect_no_call "the apply writes no protection" "PUT"

if [[ "$failures" -gt 0 ]]; then
  print_line "FAIL $failures check(s) failed"
  exit 1
fi
print_line "all checks hold"
exit 0
