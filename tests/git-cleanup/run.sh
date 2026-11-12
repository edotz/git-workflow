#!/usr/bin/env bash
# Purpose: Check app git branch-cleanup on a throwaway repository with a bare remote: what it deletes, what it keeps.
# Usage: bash tests/git-cleanup/run.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail
# The framework takes an exported PROJECT_ROOT before the working directory; the throwaway repository is the working directory.
unset PROJECT_ROOT AOS_ROOT SESSION_DIR AOS_TIER_CHAIN

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

# A legacy branch that master has, one commit behind it, and a branch just cut at the tip of master.
git -C "$repo" branch --no-track legacy/old master~1
git -C "$repo" branch --no-track fix/fresh master

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
  (cd "$repo" && env GIT_WORKFLOW_MAIN_BRANCH=master GIT_WORKFLOW_RELEASE_BRANCH=1.x GIT_WORKFLOW_LEGACY_BRANCHES="legacy/*" bash "$cleanup" "$@" 2>&1 </dev/null)
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

ok=no
if has_branch legacy/old && [[ "$out" != *"legacy/old"* ]]; then ok=yes; fi
case_result "a branch of GIT_WORKFLOW_LEGACY_BRANCHES is kept and not even reported" "$ok"

ok=no
if has_branch fix/fresh && [[ "$out" == *"kept fix/fresh"* && "$out" == *"same commit as the main branch"* ]]; then ok=yes; fi
case_result "a branch at the same commit as the main branch is kept and says why" "$ok"

rc=0
out="$(run_cleanup --force --remote-only)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"kept the remote branches"* ]] \
  && git -C "$remote" rev-parse --verify --quiet refs/heads/fix/remote-merged >/dev/null; then ok=yes; fi
case_result "a remote that is no GitHub remote keeps its merged branch and says why" "$ok"

# The remote side: origin looks like a GitHub repository and the tool image and gh are stubs; the stub docker runs the
# tool on the host and swaps the GitHub URL of the script for the bare remote.
stubs="${work}/stubs"
mkdir "$stubs"
cat > "${stubs}/docker" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  image) exit 0 ;;
  run)
    shift
    while [[ $# -gt 0 && "$1" != edotz-git-workflow-tools:* ]]; do shift; done
    shift
    args=()
    for arg in "$@"; do
      args+=("${arg/https:\/\/github.com\/o\/r.git/${STUB_REMOTE}}")
    done
    exec "${args[@]}"
    ;;
esac
exit 1
STUB
cat > "${stubs}/gh" <<'STUB'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "auth token") echo "stub-token" ;;
  "pr list") echo 0 ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${stubs}/docker" "${stubs}/gh"

run_remote_cleanup() {
  (cd "$repo" && env PATH="${stubs}:${PATH}" STUB_REMOTE="$remote" GIT_WORKFLOW_MAIN_BRANCH=master GIT_WORKFLOW_RELEASE_BRANCH=1.x GIT_WORKFLOW_LEGACY_BRANCHES="legacy/*" bash "$cleanup" --force --remote-only 2>&1 </dev/null)
}

has_remote_branch() {
  git -C "$remote" rev-parse --verify --quiet "refs/heads/$1" >/dev/null
}

git -C "$repo" remote set-url origin "https://github.com/o/r.git"

# Three remote branches behind master: one merged, one that gets a commit the local tracking ref does not know, and
# one at the tip of master.
git -C "$repo" push -q "$remote" "master~1:refs/heads/fix/remote-gone" "master~1:refs/heads/fix/remote-raced" "master:refs/heads/fix/remote-fresh"
git -C "$repo" fetch -q "$remote" "+refs/heads/*:refs/remotes/origin/*"
git -C "$repo" switch -q --no-track -c scratch origin/fix/remote-raced
echo late > "${repo}/late"
git -C "$repo" add late
git -C "$repo" commit -q -m "fix: pushed after the analysis"
git -C "$repo" push -q "$remote" "scratch:refs/heads/fix/remote-raced"
git -C "$repo" switch -q fix/current-merged
git -C "$repo" branch -q -D scratch
git -C "$repo" update-ref refs/remotes/origin/fix/remote-raced "$(git -C "$repo" rev-parse master~1)"

rc=0
out="$(run_remote_cleanup)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"deleted origin/fix/remote-gone"* ]] && ! has_remote_branch fix/remote-gone; then ok=yes; fi
case_result "a merged remote branch is deleted on origin" "$ok"

ok=no
if has_remote_branch fix/remote-raced && [[ "$out" == *"kept origin/fix/remote-raced"* ]]; then ok=yes; fi
case_result "a branch that received a commit after the analysis is kept, the fetch before the deletion shows it" "$ok"

ok=no
if has_remote_branch fix/remote-fresh && [[ "$out" == *"kept origin/fix/remote-fresh"* && "$out" == *"same commit as the main branch"* ]]; then ok=yes; fi
case_result "a remote branch at the same commit as the main branch is kept" "$ok"

git -C "$repo" remote set-url origin "https://gitlab.example.org/o/r.git"
git -C "$remote" update-ref refs/heads/fix/remote-other-host "$(git -C "$repo" rev-parse master~1)"
git -C "$repo" update-ref refs/remotes/origin/fix/remote-other-host "$(git -C "$repo" rev-parse master~1)"
rc=0
out="$(run_remote_cleanup)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"not a github.com repository"* ]] && has_remote_branch fix/remote-other-host; then ok=yes; fi
case_result "an origin that is not on github.com keeps its remote branches and says why" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
