#!/usr/bin/env bash
# Test of app git pr: the title is linted with commitlint, a dry run too, and a branch prefix that is no commitlint
# type is refused, never rewritten. Nothing leaves the machine: every run ends before the push.
# Usage: bash tests/git-pr/title.sh   (BU_ROOT must point at the framework bin directory)
set -euo pipefail

TEST_DIR="${BASH_SOURCE[0]%/*}"
PLUGIN_ROOT="$(cd "${TEST_DIR}/../.." && pwd -P)"
export PLUGIN_ROOT
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
: "${BU_ROOT:?BU_ROOT must point at the framework bin directory}"

REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT

export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
export GIT_WORKFLOW_MAIN_BRANCH="master"
unset GH_TOKEN

FAILS=0
OUT=""
RC=0

fail() {
  printf 'FAIL: %s\n' "$1"
  FAILS=$((FAILS + 1))
}

pass() {
  printf 'ok: %s\n' "$1"
}

# Run the command in the throwaway repository; sets OUT (stdout and stderr) and RC.
run_pr() {
  RC=0
  OUT="$(cd "$REPO" && bash "${PLUGIN_ROOT}/bin/modules/git/pr.sh" "$@" 2>&1)" || RC=$?
}

expect_out() {
  if [[ "$OUT" == *"$1"* ]]; then
    pass "$2"
  else
    fail "$2: output lacks '$1'"
    printf '%s\n' "$OUT"
  fi
}

expect_rc() {
  if [[ "$RC" -eq "$1" ]]; then
    pass "$2"
  else
    fail "$2: exit ${RC}, expected ${1}"
    printf '%s\n' "$OUT"
  fi
}

commit() {
  git -C "$REPO" -c core.hooksPath=/dev/null commit -q --allow-empty -m "$1"
}

mkdir "${REPO}/.agentic-os"
git -C "$REPO" init -q -b master
git -C "$REPO" remote add origin "https://github.com/example/demo.git"
printf 'components:\n  - name: app\n    paths: ["."]\n    checks: ["true"]\n' > "${REPO}/components.yaml"
commit "chore: start the repository"

# A branch prefix that is no commitlint type: the title becomes "feature: x" and is refused as it is.
git -C "$REPO" switch -q -c feature/x
commit "feat: first change"
commit "feat: second change"
run_pr --dry-run
expect_rc 3 "dry run refuses the branch prefix feature"
expect_out "did not pass commitlint" "the refusal names commitlint"
expect_out "type must be one of" "the refusal gives the commitlint reason"
expect_out "'feature: x'" "the title is refused as built, not rewritten"
if [[ "$OUT" == *"branch"*"feature/x"* ]]; then
  fail "a refused dry run prints no pull request"
else
  pass "a refused dry run prints no pull request"
fi

# The same branch refused without the dry run, before the push and before any token is needed.
run_pr
expect_rc 3 "pr refuses the branch prefix feature"
expect_out "nothing was pushed" "the refusal says that nothing was pushed"

# A prefix that is a commitlint type gives a title that passes.
git -C "$REPO" switch -q master
git -C "$REPO" switch -q -c feat/x
commit "feat: first change"
commit "feat: second change"
run_pr --dry-run
expect_rc 0 "dry run passes the branch prefix feat"
expect_out "feat: x" "the title is the branch made readable"

# Several conventional commits on a branch without a prefix: the title is the branch name in words and is refused.
git -C "$REPO" switch -q master
git -C "$REPO" switch -q -c topic-name
commit "feat: first change"
commit "feat: second change"
run_pr --dry-run
expect_rc 3 "dry run refuses a branch name that is no conventional title"
expect_out "'Topic name'" "the refusal names the title"

if [[ "$FAILS" -ne 0 ]]; then
  printf '%s check(s) failed\n' "$FAILS"
  exit 1
fi
echo "all checks passed"
