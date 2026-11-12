#!/usr/bin/env bash
# Purpose: Check the runs field of app git workflow-status on a throwaway repository: the recent workflow runs from a
#          stubbed gh, and the empty field without a gh credential, without a remote, when the runs cannot be read
#          and when gh answers with no JSON array. The case of no gh binary is not covered: the tool image needs docker.
# Usage: bash tests/git-status/runs.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail
# The framework takes an exported PROJECT_ROOT before the working directory; the throwaway repository is the working directory.
unset PROJECT_ROOT AOS_ROOT SESSION_DIR AOS_TIER_CHAIN

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
status="${root}/bin/modules/git/workflow-status.sh"
failed=0

case_result() {
  if [[ "$2" == "yes" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failed=1
  fi
}

work="$(mktemp -d)"
finish() { rm -rf "$work"; }
trap finish EXIT

repo="${work}/r"
git init -q -b master "$repo"
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.com
git -C "$repo" config core.hooksPath /dev/null
git -C "$repo" remote add origin "https://github.com/example/demo.git"
mkdir "${repo}/.agentic-os"
printf '{"name":"o","version":"1.0.0"}\n' > "${repo}/package.json"
printf 'components:\n  - name: object\n    paths: ["."]\n    version_files: [package.json]\n' > "${repo}/components.yaml"
git -C "$repo" add .
git -C "$repo" commit -q -m "chore: init"

# A stub gh: AUTH decides the answer of `auth status`, LIST the answer of `run list`; the arguments of the run list
# are written to the file named by CALLS.
stubs="${work}/stubs"
mkdir "$stubs"
cat > "${stubs}/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status")
    exit "${STUB_AUTH:-0}"
    ;;
  "run list")
    printf '%s\n' "$*" >> "$STUB_CALLS"
    if [[ "${STUB_LIST:-ok}" == "fail" ]]; then
      exit 1
    fi
    if [[ "${STUB_LIST:-ok}" == "text" ]]; then
      echo "not json"
      exit 0
    fi
    printf '[{"name":"status-checks","status":"completed","conclusion":"success","url":"https://example.test/run/1","createdAt":"2026-11-11T10:00:00Z","headBranch":"master"}]\n'
    ;;
  *)
    exit 1
    ;;
esac
STUB
chmod +x "${stubs}/gh"
calls="${work}/calls"

run_status() {
  (cd "$repo" && env -u GH_TOKEN PATH="${stubs}:${PATH}" STUB_CALLS="$calls" "$@" bash "$status" 2>/dev/null)
}

out=""
ok=no
out="$(run_status env STUB_AUTH=0 STUB_LIST=ok)" || out=""
if [[ "$(jq -r '.runs | length' <<< "$out")" == "1" && "$(jq -r '.runs[0].name' <<< "$out")" == "status-checks" \
  && "$(jq -r '.runs[0].conclusion' <<< "$out")" == "success" ]]; then ok=yes; fi
case_result "the runs field holds the runs the stubbed gh returns" "$ok"

ok=no
if [[ -s "$calls" && "$(<"$calls")" == *"--repo example/demo"* && "$(<"$calls")" == *"--limit 5"* ]]; then ok=yes; fi
case_result "gh is asked for five runs of the repository of origin" "$ok"

ok=no
if [[ "$(jq -r '.components | length' <<< "$out")" == "1" && "$(jq -r '.sync_status.ahead_of_release' <<< "$out")" == "0" ]]; then ok=yes; fi
case_result "the other fields of the status are still there" "$ok"

: > "$calls"
ok=no
out="$(run_status env STUB_AUTH=1)" || out=""
if [[ "$(jq -c '.runs' <<< "$out")" == "[]" && ! -s "$calls" ]]; then ok=yes; fi
case_result "the runs field is empty without a gh credential and gh is not asked for runs" "$ok"

ok=no
out="$(run_status env STUB_AUTH=0 STUB_LIST=fail)" || out=""
if [[ "$(jq -c '.runs' <<< "$out")" == "[]" && "$(jq -r '.current_branch' <<< "$out")" == "master" ]]; then ok=yes; fi
case_result "the runs field is empty when the runs cannot be read and the status still prints" "$ok"

ok=no
out="$(run_status env STUB_AUTH=0 STUB_LIST=text)" || out=""
if [[ "$(jq -c '.runs' <<< "$out")" == "[]" && "$(jq -r '.current_branch' <<< "$out")" == "master" ]]; then ok=yes; fi
case_result "the runs field is empty when gh answers with text that is no JSON array" "$ok"

: > "$calls"
git -C "$repo" remote remove origin
ok=no
out="$(run_status env STUB_AUTH=0 STUB_LIST=ok)" || out=""
if [[ "$(jq -c '.runs' <<< "$out")" == "[]" && ! -s "$calls" && "$(jq -r '.current_branch' <<< "$out")" == "master" ]]; then ok=yes; fi
case_result "the runs field is empty without a remote and the status still prints" "$ok"

exit "$failed"
