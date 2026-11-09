#!/usr/bin/env bash
# Test of app git pr on a throwaway repository: the dry run, the refusal of the main branch and the refusal of a
# red check. Nothing leaves the machine: the dry run and the refusals end before the push.
# Usage: bash tests/git-pr/dry-run.sh   (BU_ROOT must point at the framework bin directory)
set -euo pipefail

TEST_DIR="${BASH_SOURCE[0]%/*}"
PLUGIN_ROOT="$(cd "${TEST_DIR}/../.." && pwd -P)"
export PLUGIN_ROOT
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

# Check that OUT holds a text.
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

write_components() {
  printf 'components:\n  - name: app\n    paths: ["."]\n    checks: [%s]\n' "$1" > "${REPO}/components.yaml"
}

mkdir "${REPO}/.agentic-os"
git -C "$REPO" init -q -b master
git -C "$REPO" remote add origin "https://github.com/example/demo.git"
commit "chore: start the repository"
write_components '"true"'

snapshot() {
  git -C "$REPO" status --porcelain
  git -C "$REPO" for-each-ref
}

# Main branch refused
run_pr --dry-run
expect_rc 1 "main branch refused"
expect_out "open the pull request from another branch" "main branch refusal names the cause"

# One commit: the title is its subject
git -C "$REPO" checkout -q -b feat/add-login
commit "feat: add login"
before="$(snapshot)"
run_pr --dry-run
expect_rc 0 "dry run, one commit"
expect_out "feat/add-login" "dry run prints the branch"
expect_out "feat: add login" "dry run prints the title of the only commit"
expect_out "- feat: add login" "dry run prints the body"
if [[ "$(snapshot)" == "$before" ]]; then
  pass "dry run changes nothing"
else
  fail "dry run changed the repository"
fi

# Several commits: the title is the branch name made readable, the body lists the subjects oldest first
commit "fix: keep the session"
run_pr --dry-run --draft
expect_rc 0 "dry run, several commits"
expect_out "feat: add login" "dry run makes a conventional title of the branch name"
if [[ "$OUT" == *"- feat: add login"*"- fix: keep the session"* ]]; then
  pass "dry run lists the subjects oldest first"
else
  fail "dry run body order wrong"
  printf '%s\n' "$OUT"
fi

# Red check refused
write_components '"false"'
run_pr --dry-run
expect_rc 1 "red check refused"
expect_out "the minimum check is red" "red check refusal names the cause"

if [[ "$FAILS" -gt 0 ]]; then
  printf '%s check(s) failed\n' "$FAILS"
  exit 1
fi
printf 'all checks passed\n'
