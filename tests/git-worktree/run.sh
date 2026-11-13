#!/usr/bin/env bash
# Purpose: Check app git worktree --start on a throwaway repository with a bare remote: the worktree gets a new branch, and a branch that exists is refused.
# Usage: bash tests/git-worktree/run.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail
# The framework takes an exported PROJECT_ROOT before the working directory; the throwaway repository is the working directory.
unset PROJECT_ROOT AOS_ROOT SESSION_DIR AOS_TIER_CHAIN

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
worktree="${root}/bin/modules/git/worktree.sh"
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

remote="${work}/remote.git"
repo="${work}/r"
trees="${work}/trees"
git init -q --bare -b master "$remote"
git init -q -b master "$repo"
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.com
git -C "$repo" config core.hooksPath /dev/null
git -C "$repo" remote add origin "$remote"
mkdir "${repo}/.agentic-os"
echo 0 > "${repo}/f"
git -C "$repo" add f
git -C "$repo" commit -q -m "chore: init"
git -C "$repo" push -q origin master
git -C "$repo" fetch -q origin

run_worktree() {
  (cd "$repo" && env GIT_WORKFLOW_MAIN_BRANCH=master GIT_WORKFLOW_WORKTREE_DIR="$trees" bash "$worktree" "$@" 2>&1)
}

run_worktree_stdout() {
  (cd "$repo" && env GIT_WORKFLOW_MAIN_BRANCH=master GIT_WORKFLOW_WORKTREE_DIR="$trees" bash "$worktree" "$@" 2>/dev/null)
}

rc=0
out="$(run_worktree_stdout --start fix/new-one)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == "${trees}/r/fix-new-one" && -d "$out" \
  && "$(git -C "$out" rev-parse --abbrev-ref HEAD)" == "fix/new-one" \
  && "$(git -C "$out" rev-parse HEAD)" == "$(git -C "$repo" rev-parse master)" ]]; then ok=yes; fi
case_result "a new branch gets a worktree at the head of the main branch" "$ok"

git -C "$repo" branch --no-track fix/local-only
rc=0
out="$(run_worktree --start fix/local-only)" || rc=$?
ok=no
if [[ "$rc" -eq 1 && "$out" == *"exists locally"* && ! -d "${trees}/r/fix-local-only" ]]; then ok=yes; fi
case_result "a branch that exists locally is refused and no worktree is made" "$ok"

git -C "$repo" push -q origin "master:refs/heads/fix/only-remote"
git -C "$repo" fetch -q origin
rc=0
out="$(run_worktree --start fix/only-remote)" || rc=$?
ok=no
if [[ "$rc" -eq 1 && "$out" == *"exists on origin"* && ! -d "${trees}/r/fix-only-remote" ]] \
  && ! git -C "$repo" rev-parse --verify --quiet refs/heads/fix/only-remote >/dev/null; then ok=yes; fi
case_result "a branch that exists only on origin is refused before anything is created" "$ok"

rc=0
out="$(run_worktree --start fix/new-one)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"already exists"* ]]; then ok=yes; fi
case_result "a worktree that exists is refused" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
