#!/usr/bin/env bash
# Purpose: Check app git branch-cleanup on a throwaway repository with a bare remote: what it deletes, what it keeps.
# Usage: bash tests/git-cleanup/run.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
cleanup="${root}/bin/modules/git/branch-cleanup.sh"
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

# A branch whose commit master has by a fast forward merge.
git -C "$repo" switch -q -c fix/merged-ff
echo ff > "${repo}/ff"
git -C "$repo" add ff
git -C "$repo" commit -q -m "fix: ff"
git -C "$repo" switch -q master
git -C "$repo" merge -q --ff-only fix/merged-ff

# A branch of two commits that master has as one squash commit.
git -C "$repo" switch -q -c fix/merged-squash
echo s1 > "${repo}/s1"
git -C "$repo" add s1
git -C "$repo" commit -q -m "fix: s1"
echo s2 > "${repo}/s2"
git -C "$repo" add s2
git -C "$repo" commit -q -m "fix: s2"
git -C "$repo" switch -q master
git -C "$repo" -c merge.ff=true merge -q --squash fix/merged-squash >/dev/null
git -C "$repo" commit -q -m "fix: squash"

# A merged branch that is protected by its name, and one that is checked out.
git -C "$repo" branch --no-track backport/merged master
git -C "$repo" branch --no-track fix/current-merged master

# A branch with a commit that master lacks.
git -C "$repo" switch -q -c fix/unmerged
echo u > "${repo}/u"
git -C "$repo" add u
git -C "$repo" commit -q -m "fix: unmerged"

git -C "$repo" push -q origin master
git -C "$repo" push -q origin master:refs/heads/fix/remote-merged
git -C "$repo" fetch -q origin
git -C "$repo" switch -q fix/current-merged

run_cleanup() {
  (cd "$repo" && env GIT_WORKFLOW_MAIN_BRANCH=master GIT_WORKFLOW_RELEASE_BRANCH=1.x bash "$cleanup" "$@" 2>&1 </dev/null)
}

has_branch() {
  git -C "$repo" rev-parse --verify --quiet "refs/heads/$1" >/dev/null
}

all_present=yes
for b in fix/merged-ff fix/merged-squash backport/merged fix/current-merged fix/unmerged; do
  if ! has_branch "$b"; then all_present=no; fi
done
case_result "the fixture holds the five local branches" "$all_present"

rc=0
out="$(run_cleanup --dry-run --local-only)" || rc=$?
all_present=yes
for b in fix/merged-ff fix/merged-squash backport/merged fix/current-merged fix/unmerged; do
  if ! has_branch "$b"; then all_present=no; fi
done
ok=no
if [[ "$rc" -eq 0 && "$all_present" == "yes" && "$out" == *"merged: fix/merged-ff"* && "$out" == *"merged: fix/merged-squash"* ]]; then ok=yes; fi
case_result "a dry run reports the merged branches and deletes nothing" "$ok"

rc=0
out="$(run_cleanup --local-only)" || rc=$?
all_present=yes
for b in fix/merged-ff fix/merged-squash; do
  if ! has_branch "$b"; then all_present=no; fi
done
ok=no
if [[ "$rc" -eq 0 && "$all_present" == "yes" && "$out" == *"Not interactive"* ]]; then ok=yes; fi
case_result "without --force and without a terminal nothing is deleted" "$ok"

rc=0
out="$(run_cleanup --force --local-only)" || rc=$?
ok=no
if [[ "$rc" -eq 0 ]] && ! has_branch fix/merged-ff && ! has_branch fix/merged-squash; then ok=yes; fi
case_result "--force deletes the fast forward and the squash merged branch" "$ok"

ok=no
if [[ "$out" == *"deleted fix/merged-ff"* && "$out" == *"deleted fix/merged-squash"* ]]; then ok=yes; fi
case_result "the output names each deleted branch" "$ok"

ok=no
if has_branch fix/current-merged && [[ "$out" == *"kept fix/current-merged"* ]]; then ok=yes; fi
case_result "the checked out merged branch is kept and named" "$ok"

ok=no
if has_branch backport/merged && has_branch fix/unmerged && has_branch master; then ok=yes; fi
case_result "a protected name, an unmerged branch and the main branch are kept" "$ok"

rc=0
out="$(run_cleanup --force --remote-only)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"kept the remote branches"* ]] \
  && git -C "$remote" rev-parse --verify --quiet refs/heads/fix/remote-merged >/dev/null; then ok=yes; fi
case_result "a remote that is no GitHub remote keeps its merged branch and says why" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
