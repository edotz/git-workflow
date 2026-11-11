#!/usr/bin/env bash
# Purpose: Check app git lint-commit: commitlint alone decides, there is no bypass in the script. A conventional subject
#          passes; a subject that is not conventional fails, a subject that starts with Merge or Revert included; the
#          subjects commitlint ignores by default (Merge branch, Merge pull request, Revert) pass.
# Usage: bash tests/git-commit/lint.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it); needs npm install in the plugin root
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
: "${BU_ROOT:?BU_ROOT must point at the framework bin directory}"

lint="${root}/bin/modules/git/lint-commit.sh"
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

# Run lint-commit on a message; sets OUT (stdout and stderr) and RC.
lint_message() {
  printf '%s\n' "$1" > "${work}/msg"
  RC=0
  OUT="$(bash "$lint" "${work}/msg" 2>&1)" || RC=$?
}

lint_message "feat(git): add the lint test"
case_result "a conventional subject passes" "$([[ "$RC" -eq 0 ]] && echo yes || echo no)"

lint_message "added some things"
case_result "a subject that is not conventional is refused with the commitlint reason" "$([[ "$RC" -ne 0 && "$OUT" == *"type may not be empty"* ]] && echo yes || echo no)"

lint_message "Merge things together"
case_result "a subject that starts with Merge but is no merge subject is refused" "$([[ "$RC" -ne 0 && "$OUT" == *"type may not be empty"* ]] && echo yes || echo no)"

lint_message "Merge branch 'feat/x' into master"
case_result "a Merge branch subject passes through the commitlint default ignores" "$([[ "$RC" -eq 0 ]] && echo yes || echo no)"

lint_message "Merge pull request #12 from own/feat/x"
case_result "a Merge pull request subject passes through the commitlint default ignores" "$([[ "$RC" -eq 0 ]] && echo yes || echo no)"

lint_message 'Revert "feat: add the lint test"'
case_result "a Revert subject passes through the commitlint default ignores" "$([[ "$RC" -eq 0 ]] && echo yes || echo no)"

lint_message "Reverted the change by hand"
case_result "a subject that starts with Revert but is no revert subject is refused" "$([[ "$RC" -ne 0 && "$OUT" == *"type may not be empty"* ]] && echo yes || echo no)"

RC=0
OUT="$(bash "$lint" 2>&1)" || RC=$?
case_result "no file is a usage error" "$([[ "$RC" -eq 2 && "$OUT" == *"Usage"* ]] && echo yes || echo no)"

exit "$failed"
