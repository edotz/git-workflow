#!/usr/bin/env bash
# Purpose: Check app git promote on a throwaway repository with a bare remote: the dry run and the refusals.
# Usage: bash tests/git-promote/ff.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
promote="${root}/bin/modules/git/promote.sh"
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
c0="$(git -C "$repo" rev-parse HEAD)"
echo 1 > "${repo}/f"
git -C "$repo" commit -q -am "chore(object): release v1.0.0"
c1="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" tag v1.0.0
echo 2 > "${repo}/f"
git -C "$repo" commit -q -am "feat: later"
c2="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" tag v2.0.0
git -C "$repo" push -q origin master
git -C "$repo" push -q origin "${c0}:refs/heads/release"
git -C "$repo" fetch -q origin

run_promote() {
  (cd "$repo" && env -u GH_TOKEN TOKEN_SERVICE_URL=http://127.0.0.1:9 MAIN_BRANCH=master RELEASE_BRANCH=release bash "$promote" "$@" 2>&1)
}

rc=0
out="$(run_promote v1.0.0 --dry-run)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"$c1"* && "$out" != *"$c2"* ]]; then ok=yes; fi
case_result "the dry run names the commit of the tag, not the head of master" "$ok"

ok=no
if [[ "$(git -C "$remote" rev-parse refs/heads/release)" == "$c0" ]]; then ok=yes; fi
case_result "the dry run moves nothing on the remote" "$ok"

rc=0
out="$(run_promote v2.0.0 --dry-run)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"not a release tag"* ]]; then ok=yes; fi
case_result "a tag whose commit is no release commit is refused" "$ok"

rc=0
out="$(run_promote v9.9.9 --dry-run)" || rc=$?
ok=no
if [[ "$rc" -eq 4 ]]; then ok=yes; fi
case_result "an unknown tag is refused with exit 4" "$ok"

git -C "$repo" checkout -q -b side "$c0"
echo side > "${repo}/g"
git -C "$repo" add g
git -C "$repo" commit -q -m "chore: side"
side="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" push -q -f origin "${side}:refs/heads/release"
git -C "$repo" fetch -q origin
git -C "$repo" checkout -q master
rc=0
out="$(run_promote v1.0.0 --dry-run)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"not a fast-forward"* ]]; then ok=yes; fi
case_result "a diverged release branch is refused" "$ok"

git -C "$repo" push -q -f origin "${c1}:refs/heads/release"
git -C "$repo" fetch -q origin
rc=0
out="$(run_promote v1.0.0 --dry-run)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"already: nothing to promote"* ]]; then ok=yes; fi
case_result "a release branch at the tag already does nothing" "$ok"

git -C "$repo" push -q origin ":refs/heads/release"
git -C "$repo" fetch -q -p origin
git -C "$repo" branch -q -D side
rc=0
out="$(run_promote v1.0.0 --dry-run)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"absent"* && "$out" == *"$c1"* ]]; then ok=yes; fi
case_result "an absent release branch is created at the commit of the tag" "$ok"

rc=0
out="$(cd "$repo" && env -u GH_TOKEN MAIN_BRANCH=master RELEASE_BRANCH=master bash "$promote" v1.0.0 --dry-run 2>&1)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"nothing to promote"* ]]; then ok=yes; fi
case_result "a release branch equal to the main branch does nothing" "$ok"

rc=0
out="$(run_promote v1.0.0)" || rc=$?
ok=no
if [[ "$rc" -eq 2 ]]; then ok=yes; fi
case_result "neither --dry-run nor --apply is a usage error" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
