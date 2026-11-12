#!/usr/bin/env bash
# Purpose: Run bin/modules/git/stage.sh against stub docker, gh and curl commands: the report of the live stage of the
#          master ruleset (none, development, production, drift), the dry run changing nothing, the apply switching the
#          ruleset in both directions through the token of the App, an apply with nothing to switch writing nothing, and
#          the refusals (unknown stage, apply without a stage, apply without the App id).
# Usage: bash tests/git-stage/run.sh
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

# The stubs are those of tests/git-rules/sync.sh: the tool image runs docker, the host runs gh and curl.
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
echo "curl token-request" >>"${STUB_DIR}/calls.log"
printf '{"token":"stub-installation-token"}\n200'
STUB

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
shopt -s nullglob
case "${method} ${path}" in
  "GET repos/acme/widgets/rulesets")
    files=("${dir}"/rulesets/*.json)
    if [[ ${#files[@]} -eq 0 ]]; then echo '[]'; else jq -c -s '[.[] | {id, name}]' "${files[@]}"; fi
    ;;
  "GET repos/acme/widgets/rulesets/"*)
    cat "${dir}/rulesets/${path##*/}.json"
    ;;
  "POST repos/acme/widgets/rulesets" | "PUT repos/acme/widgets/rulesets/"*)
    if [[ -e "${dir}/fail-write" ]]; then
      echo "gh: HTTP 500" >&2
      exit 1
    fi
    ;;&
  "POST repos/acme/widgets/rulesets")
    body="$(cat)"
    id=$(($(<"${dir}/counter") + 1))
    echo "$id" >"${dir}/counter"
    echo "gh POST ${path} name=$(jq -r '.name' <<<"$body")" >>"${dir}/calls.log"
    jq -c --argjson id "$id" '. + {id: $id}' <<<"$body" >"${dir}/rulesets/${id}.json"
    echo "{\"id\":${id}}"
    ;;
  "PUT repos/acme/widgets/rulesets/"*)
    body="$(cat)"
    id="${path##*/}"
    echo "gh PUT ${path} name=$(jq -r '.name' <<<"$body")" >>"${dir}/calls.log"
    jq -c --argjson id "$id" '. + {id: $id}' <<<"$body" >"${dir}/rulesets/${id}.json"
    echo "{\"id\":${id}}"
    ;;
  *)
    echo "gh unexpected ${method} ${path}" >>"${dir}/calls.log"
    exit 1
    ;;
esac
STUB
chmod +x "${STUBS}/docker" "${STUBS}/curl" "${STUBS}/gh"

# Create a throwaway project: a git repository whose origin is acme/widgets and an empty .agentic-os directory.
# Args: $1 - directory  $2 - content of its .env
make_project() {
  mkdir -p "$1/.agentic-os"
  git -C "$1" init -q
  git -C "$1" remote add origin git@github.com:acme/widgets.git
  printf '%s' "$2" >"$1/.env"
  return 0
}

# Start a fresh stub state: no rulesets and an empty call log. Sets STUB_DIR.
new_state() {
  STUB_DIR="$(mktemp -d -p "$WORK")"
  mkdir -p "${STUB_DIR}/rulesets"
  echo 0 >"${STUB_DIR}/counter"
  : >"${STUB_DIR}/calls.log"
  return 0
}

# Run stage.sh in a project with a clean environment and the stubs first on PATH. Sets OUT and RC.
# Args: $1 - project directory  $2.. - arguments of stage
run_stage() {
  local project="$1"
  shift
  RC=0
  OUT="$(cd "$project" && env -i HOME="$WORK" PATH="${STUBS}:${PATH}" BU_ROOT="$BU_ROOT" PLUGIN_ROOT="$ROOT" PLUGIN_LIB="${ROOT}/bin/lib" \
    GIT_WORKFLOW_RELEASE_BRANCH=release STUB_DIR="$STUB_DIR" bash "${ROOT}/bin/modules/git/stage.sh" "$@" 2>&1)" || RC=$?
  return 0
}

# Run rules-sync to put the master ruleset into a stage.
# Args: $1 - project directory  $2 - stage
seed() {
  (cd "$1" && env -i HOME="$WORK" PATH="${STUBS}:${PATH}" BU_ROOT="$BU_ROOT" PLUGIN_ROOT="$ROOT" PLUGIN_LIB="${ROOT}/bin/lib" \
    GIT_WORKFLOW_RELEASE_BRANCH=release STUB_DIR="$STUB_DIR" bash "${ROOT}/bin/modules/git/rules-sync.sh" --apply --stage "$2" >/dev/null 2>&1)
  : >"${STUB_DIR}/calls.log"
  return 0
}

# Count the writes (POST and PUT) in the call log. Sets COUNT.
count_writes() {
  local line
  COUNT=0
  while IFS= read -r line; do
    case "$line" in
      "gh POST "* | "gh PUT "*) COUNT=$((COUNT + 1)) ;;
    esac
  done <"${STUB_DIR}/calls.log"
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

# Pass when OUT does not hold the text.
expect_not_out() {
  local status=0
  if [[ "$OUT" == *"$2"* ]]; then status=1; fi
  verdict "$1" "$status"
  return 0
}

# Pass when the call log holds a line that starts with the prefix.
expect_logged() {
  local line status=1
  while IFS= read -r line; do
    case "$line" in
      "$2"*) status=0 ;;
    esac
  done <"${STUB_DIR}/calls.log"
  verdict "$1" "$status"
  return 0
}

# Pass when OUT holds the text.
expect_out() {
  local status=1
  if [[ "$OUT" == *"$2"* ]]; then status=0; fi
  verdict "$1" "$status"
  return 0
}

expect_equal() {
  local status=1
  if [[ "$2" == "$3" ]]; then status=0; fi
  verdict "$1 (got $2, want $3)" "$status"
  return 0
}

APP="${WORK}/project-app"
make_project "$APP" $'GIT_WORKFLOW_APP_ID=424242\n'
NOAPP="${WORK}/project-noapp"
make_project "$NOAPP" ""

new_state
run_stage "$APP"
expect_equal "report without a master ruleset exits 0" "$RC" 0
expect_out "report without a master ruleset says none" "live stage: none"

seed "$APP" development
run_stage "$APP"
expect_out "report names development" "live stage: development"
run_stage "$APP" development
expect_out "the same stage says it is unchanged" "unchanged: already development"
count_writes
expect_equal "the same stage writes nothing" "$COUNT" 0

run_stage "$APP" production
expect_equal "dry run exits 0" "$RC" 0
expect_out "dry run names the change" "would switch: development -> production"
count_writes
expect_equal "dry run writes nothing" "$COUNT" 0

run_stage "$APP" production --apply
expect_equal "apply exits 0" "$RC" 0
expect_logged "apply asks the token service before it writes" "curl token-request"
expect_out "apply names the switch" "switched: development -> production"
count_writes
expect_equal "apply writes the master ruleset once" "$COUNT" 1
run_stage "$APP"
expect_out "report names production after the apply" "live stage: production"

: >"${STUB_DIR}/calls.log"
run_stage "$APP" production --apply
count_writes
expect_equal "apply of the live stage writes nothing" "$COUNT" 0

run_stage "$APP" development --apply
expect_out "apply back names the switch" "switched: production -> development"
run_stage "$APP"
expect_out "report names development after the way back" "live stage: development"

master_file="$(printf '%s\n' "${STUB_DIR}"/rulesets/*.json | head -n 1)"
jq -c '.enforcement = "disabled"' "$master_file" >"${master_file}.new"
mv "${master_file}.new" "$master_file"
run_stage "$APP"
expect_out "a changed live ruleset is reported as drift" "live stage: drift"

new_state
seed "$APP" production
master_file="$(printf '%s\n' "${STUB_DIR}"/rulesets/*.json | head -n 1)"
jq -c '(.rules[] | select(.type == "pull_request") | .parameters) += {dismissal_restriction: {enabled: false, allowed_actors: []}, required_reviewers: []}
  | (.rules[] | select(.type == "required_status_checks") | .parameters) += {do_not_enforce_on_create: false}' "$master_file" >"${master_file}.new"
mv "${master_file}.new" "$master_file"
run_stage "$APP"
expect_out "default parameters added by GitHub do not make a drift" "live stage: production"
run_stage "$APP" production
expect_out "the stage is unchanged with those parameters" "unchanged: already production"

new_state
seed "$APP" development
touch "${STUB_DIR}/fail-write"
run_stage "$APP" production --apply
expect_equal "a failing write ends with the status of rules-sync" "$RC" 1
expect_out "a failing write names rules-sync" "rules-sync failed"
expect_not_out "a failing write does not report a switch" "switched:"
rm -f "${STUB_DIR}/fail-write"

run_stage "$APP" --apply production
expect_out "the flag before the stage switches as well" "switched: development -> production"

run_stage "$APP" staging
expect_equal "an unknown stage is a usage error" "$RC" 2
run_stage "$APP" --apply
expect_equal "apply without a stage is a usage error" "$RC" 2
new_state
run_stage "$NOAPP" production --apply
expect_equal "apply without the App id is a config error" "$RC" 3

if [[ "$failures" -ne 0 ]]; then
  print_line "${failures} check(s) failed"
  exit 1
fi
print_line "all checks passed"
