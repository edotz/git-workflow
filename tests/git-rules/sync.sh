#!/usr/bin/env bash
# Purpose: Run bin/modules/git/rules-sync.sh against stub docker, gh and curl commands and check its outcomes: create,
#          update, unchanged and skipped, the dry-run writing nothing, the token request before the first write, a second
#          apply changing nothing, the stage reaching the master ruleset and GIT_WORKFLOW_APP_ID the bypass actor.
# Usage: bash tests/git-rules/sync.sh
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
EXTRA_ENV=()

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
token="no"
if [[ -n "${GH_TOKEN:-}" ]]; then token="yes"; fi
path="${endpoint%%\?*}"
shopt -s nullglob
case "${method} ${path}" in
  "GET repos/acme/widgets/rulesets")
    echo "gh GET ${path} token=${token}" >>"${dir}/calls.log"
    if [[ "$token" == "no" ]]; then
      echo "gh: authentication required" >&2
      exit 4
    fi
    files=("${dir}"/rulesets/*.json)
    if [[ ${#files[@]} -eq 0 ]]; then echo '[]'; else jq -c -s '[.[] | {id, name}]' "${files[@]}"; fi
    ;;
  "GET repos/acme/widgets/rulesets/"*)
    echo "gh GET ${path} token=${token}" >>"${dir}/calls.log"
    cat "${dir}/rulesets/${path##*/}.json"
    ;;
  "POST repos/acme/widgets/rulesets")
    body="$(cat)"
    id=$(($(<"${dir}/counter") + 1))
    echo "$id" >"${dir}/counter"
    name="$(jq -r '.name' <<<"$body")"
    echo "gh POST ${path} token=${token} name=${name}" >>"${dir}/calls.log"
    jq -c --argjson id "$id" '. + {id: $id}' <<<"$body" >"${dir}/rulesets/${id}.json"
    printf '%s\n' "$body" >"${dir}/bodies/${id}-${name}.json"
    echo "{\"id\":${id}}"
    ;;
  "PUT repos/acme/widgets/rulesets/"*)
    body="$(cat)"
    id="${path##*/}"
    name="$(jq -r '.name' <<<"$body")"
    echo "gh PUT ${path} token=${token} name=${name}" >>"${dir}/calls.log"
    jq -c --argjson id "$id" '. + {id: $id}' <<<"$body" >"${dir}/rulesets/${id}.json"
    printf '%s\n' "$body" >"${dir}/bodies/${id}-${name}.json"
    echo "{\"id\":${id}}"
    ;;
  *)
    echo "gh unexpected ${method} ${path}" >>"${dir}/calls.log"
    exit 1
    ;;
esac
STUB
chmod +x "${STUBS}/docker" "${STUBS}/curl" "${STUBS}/gh"

# ============================================
# Helpers
# ============================================

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
  mkdir -p "${STUB_DIR}/rulesets" "${STUB_DIR}/bodies"
  echo 0 >"${STUB_DIR}/counter"
  : >"${STUB_DIR}/calls.log"
  return 0
}

# Run rules-sync in a project with a clean environment, the stubs first on PATH and EXTRA_ENV added. Sets OUT and RC.
# Args: $1 - project directory  $2.. - arguments of rules-sync
run_sync() {
  local project="$1"
  shift
  RC=0
  OUT="$(cd "$project" && env -i HOME="$WORK" PATH="${STUBS}:${PATH}" BU_ROOT="$BU_ROOT" PLUGIN_ROOT="$ROOT" PLUGIN_LIB="${ROOT}/bin/lib" \
    STUB_DIR="$STUB_DIR" "${EXTRA_ENV[@]}" bash "${ROOT}/bin/modules/git/rules-sync.sh" "$@" 2>&1)" || RC=$?
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

# Number of the first call-log line that starts with a prefix, 0 when none. Sets LINE_NO.
first_line_of() {
  local prefix="$1" line n=0
  LINE_NO=0
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      "$prefix"*)
        LINE_NO=$n
        return 0
        ;;
    esac
  done <"${STUB_DIR}/calls.log"
  return 0
}

# Record one check: ok when the status is 0.
# Args: $1 - label  $2 - status of the condition
verdict() {
  if [[ "$2" -eq 0 ]]; then
    print_line "ok   $1"
  else
    print_line "FAIL $1"
    failures=$((failures + 1))
  fi
  return 0
}

# Pass when OUT holds a line with the ruleset name and the word.
# Args: $1 - label  $2 - ruleset name  $3 - word
expect_line() {
  local line found=1
  while IFS= read -r line; do
    if [[ "$line" == *"$2"* && "$line" == *"$3"* ]]; then
      found=0
    fi
  done <<<"$OUT"
  verdict "$1" "$found"
  return 0
}

# Pass when the file holds the text.
# Args: $1 - label  $2 - file  $3 - text
expect_in_file() {
  local status=1
  if [[ "$(<"$2")" == *"$3"* ]]; then status=0; fi
  verdict "$1" "$status"
  return 0
}

# Fail when the file holds the text.
# Args: $1 - label  $2 - file  $3 - text
expect_not_in_file() {
  local status=0
  if [[ "$(<"$2")" == *"$3"* ]]; then status=1; fi
  verdict "$1" "$status"
  return 0
}

# Pass when two numbers are equal.
# Args: $1 - label  $2 - actual  $3 - expected
expect_equal() {
  local status=1
  if [[ "$2" == "$3" ]]; then status=0; fi
  verdict "$1 (got $2, want $3)" "$status"
  return 0
}

APP="${WORK}/project-app"
BARE="${WORK}/project-bare"
make_project "$APP" $'GIT_WORKFLOW_APP_ID=424242\n'
make_project "$BARE" $'GIT_WORKFLOW_MAIN_BRANCH=master\n'

BRANCHES=(GIT_WORKFLOW_RELEASE_BRANCH=release "GIT_WORKFLOW_LEGACY_BRANCHES=1.x,2.x")

# ============================================
# Checks
# ============================================

new_state
EXTRA_ENV=("${BRANCHES[@]}")
run_sync "$APP" --dry-run
expect_equal "dry-run exits 0" "$RC" 0
expect_line "dry-run prints master create" master create
expect_line "dry-run prints release create" release create
expect_line "dry-run prints legacy create" legacy create
count_writes
expect_equal "dry-run logs no write" "$COUNT" 0
first_line_of "curl token-request"
expect_equal "dry-run requests no token" "$LINE_NO" 0

run_sync "$APP"
count_writes
expect_equal "no flag is a dry-run and logs no write" "$COUNT" 0

run_sync "$APP" --apply
expect_equal "apply exits 0" "$RC" 0
count_writes
expect_equal "apply creates three rulesets" "$COUNT" 3
first_line_of "curl token-request"
token_line=$LINE_NO
first_line_of "gh POST "
write_line=$LINE_NO
status=1
if [[ "$token_line" -gt 0 && "$write_line" -gt "$token_line" ]]; then status=0; fi
verdict "apply logs the token request (line ${token_line}) before its first write (line ${write_line})" "$status"
expect_in_file "apply sends the token to gh" "${STUB_DIR}/calls.log" "POST repos/acme/widgets/rulesets token=yes"
master_body="$(printf '%s\n' "${STUB_DIR}"/bodies/*-master.json)"
expect_in_file "GIT_WORKFLOW_APP_ID of the .env is the bypass actor of master" "$master_body" '"actor_id":424242'
expect_not_in_file "the actor id placeholder is gone from master" "$master_body" "APP_ID_PLACEHOLDER"

run_sync "$APP" --apply
expect_equal "second apply exits 0" "$RC" 0
count_writes
expect_equal "second apply logs no new write" "$COUNT" 3
expect_line "second apply prints master unchanged" master unchanged
expect_line "second apply prints release unchanged" release unchanged
expect_line "second apply prints legacy unchanged" legacy unchanged

new_state
EXTRA_ENV=("${BRANCHES[@]}")
run_sync "$APP" --apply
master_file="$(printf '%s\n' "${STUB_DIR}"/rulesets/*.json | head -n 1)"
jq -c '.enforcement = "disabled"' "$master_file" >"${master_file}.new"
mv "${master_file}.new" "$master_file"
run_sync "$APP" --dry-run
expect_line "dry-run prints master update for a changed ruleset" master update
count_writes
expect_equal "dry-run of an update logs no further write" "$COUNT" 3
run_sync "$APP" --apply
count_writes
expect_equal "apply updates only the changed ruleset" "$COUNT" 4
first_line_of "gh PUT "
verdict "apply sends a PUT for the update" "$((LINE_NO > 0 ? 0 : 1))"
run_sync "$APP" --dry-run
expect_line "dry-run prints master unchanged after the update" master unchanged

new_state
EXTRA_ENV=()
run_sync "$APP" --apply --stage production
production_body="$(<"$(printf '%s\n' "${STUB_DIR}"/bodies/*-master.json)")"
new_state
run_sync "$APP" --apply --stage development
development_body="$(<"$(printf '%s\n' "${STUB_DIR}"/bodies/*-master.json)")"
status=0
if [[ "$production_body" == "$development_body" ]]; then status=1; fi
verdict "stage production and stage development send different master rulesets" "$status"

new_state
EXTRA_ENV=(GIT_WORKFLOW_STAGE=production)
run_sync "$APP" --apply
env_stage_body="$(<"$(printf '%s\n' "${STUB_DIR}"/bodies/*-master.json)")"
status=1
if [[ "$env_stage_body" == "$production_body" ]]; then status=0; fi
verdict "GIT_WORKFLOW_STAGE selects the stage when --stage is absent" "$status"

new_state
EXTRA_ENV=(GIT_WORKFLOW_APP_ID=777)
run_sync "$APP" --apply
expect_in_file "GIT_WORKFLOW_APP_ID of the environment is the bypass actor" \
  "$(printf '%s\n' "${STUB_DIR}"/bodies/*-master.json)" '"actor_id":777'

new_state
EXTRA_ENV=()
run_sync "$BARE" --apply
status=1
if [[ "$RC" -ne 0 && "$OUT" == *GIT_WORKFLOW_APP_ID* ]]; then status=0; fi
verdict "apply without GIT_WORKFLOW_APP_ID is refused with a message" "$status"
count_writes
expect_equal "refused apply logs no write" "$COUNT" 0
first_line_of "curl token-request"
expect_equal "refused apply requests no token" "$LINE_NO" 0

new_state
EXTRA_ENV=()
run_sync "$BARE" --dry-run
expect_equal "dry-run without GIT_WORKFLOW_APP_ID exits 0" "$RC" 0
expect_line "dry-run without GIT_WORKFLOW_APP_ID prints master create" master create

new_state
EXTRA_ENV=()
run_sync "$APP" --apply
run_sync "$BARE" --dry-run
expect_line "dry-run without GIT_WORKFLOW_APP_ID leaves an applied master unchanged" master unchanged

new_state
EXTRA_ENV=()
run_sync "$APP" --apply
expect_equal "apply with neither branch setting exits 0" "$RC" 0
expect_line "release is skipped without GIT_WORKFLOW_RELEASE_BRANCH" release skipped
expect_line "legacy is skipped without GIT_WORKFLOW_LEGACY_BRANCHES" legacy skipped
expect_line "master applies without the branch settings" master create
count_writes
expect_equal "only master is written when release and legacy are skipped" "$COUNT" 1
expect_in_file "the one write is master" "${STUB_DIR}/calls.log" "name=master"

if [[ "$failures" -gt 0 ]]; then
  print_line "${failures} check(s) failed"
  exit 1
fi
print_line "all checks hold"
exit 0
