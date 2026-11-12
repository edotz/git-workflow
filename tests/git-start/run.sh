#!/usr/bin/env bash
# Purpose: Check app git start on a throwaway repository with a bare remote: the branch is created in the checkout, and the refusals.
# Usage: bash tests/git-start/run.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
start="${root}/bin/modules/git/start.sh"
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
git -C "$repo" push -q origin master
git -C "$repo" fetch -q origin

run_start() {
  (cd "$repo" && env GIT_WORKFLOW_MAIN_BRANCH=master bash "$start" "$@" 2>&1)
}

run_start_stdout() {
  (cd "$repo" && env GIT_WORKFLOW_MAIN_BRANCH=master bash "$start" "$@" 2>/dev/null)
}

echo "uncommitted" > "${repo}/f"
rc=0
out="$(run_start_stdout feat good-one)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == "feat/good-one" ]]; then ok=yes; fi
case_result "a good start prints the name of the branch" "$ok"

ok=no
if [[ "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" == "feat/good-one" \
  && "$(git -C "$repo" rev-parse HEAD)" == "$(git -C "$repo" rev-parse master)" ]]; then ok=yes; fi
case_result "the checkout is on the branch type/name at the head of the main branch" "$ok"

ok=no
if [[ -z "$(git -C "$repo" config --get branch.feat/good-one.remote || true)" \
  && -z "$(git -C "$repo" config --get branch.feat/good-one.merge || true)" ]]; then ok=yes; fi
case_result "the new branch has no upstream" "$ok"

ok=no
if [[ "$(<"${repo}/f")" == "uncommitted" ]]; then ok=yes; fi
case_result "an uncommitted change goes along to the new branch" "$ok"
git -C "$repo" checkout -q -- f

rc=0
out="$(run_start wip bad-type)" || rc=$?
ok=no
if [[ "$rc" -eq 2 && "$out" == *"Unknown type"* && "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" == "feat/good-one" ]]; then ok=yes; fi
case_result "a type outside the commitlint types is refused with exit 2" "$ok"

for bad in "Bad-Name" "bad_name" "bad--name" "-bad" "bad-" "bad/name"; do
  rc=0
  out="$(run_start fix "$bad")" || rc=$?
  ok=no
  if [[ "$rc" -eq 2 && ( "$out" == *"Invalid name"* || "$bad" == -* ) ]]; then ok=yes; fi
  case_result "the name '${bad}' is refused with exit 2" "$ok"
done

rc=0
out="$(run_start fix)" || rc=$?
ok=no
if [[ "$rc" -eq 2 && "$out" == *"Usage"* ]]; then ok=yes; fi
case_result "a missing name is a usage error" "$ok"

rc=0
out="$(run_start feat good-one)" || rc=$?
ok=no
if [[ "$rc" -eq 1 && "$out" == *"exists locally"* ]]; then ok=yes; fi
case_result "a branch that exists locally is refused" "$ok"

rc=0
out="$(run_start_stdout fix good-one)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == "fix/good-one" \
  && "$(git -C "$repo" rev-parse HEAD)" == "$(git -C "$repo" rev-parse master)" ]]; then ok=yes; fi
case_result "the same name under another type is no clash, and the start works from another branch" "$ok"

git -C "$repo" push -q origin "master:refs/heads/fix/only-remote"
git -C "$repo" fetch -q origin
rc=0
out="$(run_start fix only-remote)" || rc=$?
ok=no
if [[ "$rc" -eq 1 && "$out" == *"exists on origin"* ]]; then ok=yes; fi
case_result "a branch that exists only on origin is refused before anything is created" "$ok"

ok=no
if ! git -C "$repo" rev-parse --verify --quiet refs/heads/fix/only-remote >/dev/null; then ok=yes; fi
case_result "the refusal creates no local branch" "$ok"

git -C "$repo" switch -q master
git -C "$repo" commit -q --allow-empty -m "chore: only local"
rc=0
out="$(run_start fix behind-origin)" || rc=$?
ok=no
if [[ "$rc" -eq 1 && "$out" == *"not in sync"* && "$out" == *"git switch master"* ]] \
  && ! git -C "$repo" rev-parse --verify --quiet refs/heads/fix/behind-origin >/dev/null; then ok=yes; fi
case_result "a main branch that differs from origin is refused before the branch is created" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
