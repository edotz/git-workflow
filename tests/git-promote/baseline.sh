#!/usr/bin/env bash
# Purpose: Check the baseline mode of app git promote on a throwaway repository with a bare remote: a release branch
#          that is not an ancestor of the release commit is tagged legacy/pre-promote and replaced, only with --confirm.
# Usage: bash tests/git-promote/baseline.sh
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

# The plugin libraries with a token.sh that fetches nothing: the token service is not part of this test.
mkdir "${work}/lib"
for f in "${root}"/bin/lib/*; do
  ln -s "$f" "${work}/lib/${f##*/}"
done
rm "${work}/lib/token.sh"
cat > "${work}/lib/token.sh" <<'EOF'
token_fetch() { printf '%s\n' "$*" >> "${TOKEN_LOG}"; return 0; }
token_drop() { return 0; }
EOF
export TOKEN_LOG="${work}/token.log"
export PLUGIN_LIB="${work}/lib"

# The remote sits inside the repository: the tool image mounts only the repository. The https URL promote builds from
# the slug is rewritten to it; origin is the ssh form of the slug, which the rewrite does not touch.
repo="${work}/r"
remote="${repo}/.remote.git"
slug="o/r"
git init -q -b master "$repo"
git init -q --bare -b master "$remote"
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.com
git -C "$repo" config core.hooksPath /dev/null
git -C "$repo" config "url.${remote}.insteadOf" "https://github.com/${slug}.git"
git -C "$repo" remote add origin "git@github.com:${slug}.git"
mkdir -p "${repo}/.git/info"
echo "/.remote.git" >> "${repo}/.git/info/exclude"
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
git -C "$repo" push -q "$remote" master
git -C "$repo" checkout -q -b side "$c0"
echo side > "${repo}/g"
git -C "$repo" add g
git -C "$repo" commit -q -m "chore: side"
side="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q master
git -C "$repo" branch -q -D side
git -C "$repo" push -q "$remote" "${side}:refs/heads/release"
git -C "$repo" fetch -q "$remote" "+refs/heads/*:refs/remotes/origin/*"

run_promote() {
  (cd "$repo" && env -u GH_TOKEN GIT_WORKFLOW_MAIN_BRANCH=master GIT_WORKFLOW_RELEASE_BRANCH=release bash "$promote" "$@" 2>&1)
}
remote_release() { git -C "$remote" rev-parse refs/heads/release; }

rc=0
out="$(run_promote v1.0.0 --dry-run)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"not a fast-forward"* && "$out" == *"legacy/pre-promote"* && "$out" == *"$side"* ]]; then ok=yes; fi
case_result "the dry run names the divergence and the baseline" "$ok"

ok=no
if [[ "$(remote_release)" == "$side" ]]; then ok=yes; fi
case_result "the dry run moves nothing on the remote" "$ok"

rc=0
out="$(run_promote v1.0.0 --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 2 && "$out" == *"--confirm"* ]]; then ok=yes; fi
case_result "an apply without --confirm is refused with exit 2" "$ok"

ok=no
if [[ "$(remote_release)" == "$side" && ! -e "$TOKEN_LOG" ]]; then ok=yes; fi
case_result "the refused apply fetches no token and moves nothing" "$ok"

rc=0
out="$(run_promote v1.0.0 --apply --confirm other/repo)" || rc=$?
ok=no
if [[ "$rc" -eq 2 && "$out" == *"other/repo"* && "$(remote_release)" == "$side" ]]; then ok=yes; fi
case_result "a --confirm that names another repository is refused with exit 2" "$ok"

rc=0
out="$(run_promote v2.0.0 --apply --confirm "$slug")" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"not a release tag"* && "$(remote_release)" == "$side" ]]; then ok=yes; fi
case_result "a tag that is no release commit is refused even with --confirm" "$ok"

rc=0
out="$(run_promote v1.0.0 --apply --confirm "$slug")" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$(remote_release)" == "$c1" ]]; then ok=yes; fi
case_result "the apply with --confirm moves the release branch to the commit of the tag" "$ok"

ok=no
if [[ "$(git -C "$remote" rev-parse refs/tags/legacy/pre-promote)" == "$side" ]]; then ok=yes; fi
case_result "the old head is kept as legacy/pre-promote" "$ok"

rc=0
out="$(run_promote v1.0.0 --apply --confirm "$slug")" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"nothing to promote"* && "$(remote_release)" == "$c1" ]]; then ok=yes; fi
case_result "a second apply finds nothing to do" "$ok"

git -C "$repo" push -q -f "$remote" "${c0}:refs/heads/release"
git -C "$repo" fetch -q "$remote" "+refs/heads/*:refs/remotes/origin/*"
rc=0
out="$(run_promote v1.0.0 --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" != *"legacy"* && "$(remote_release)" == "$c1" ]]; then ok=yes; fi
case_result "a fast-forward needs no --confirm and keeps no legacy tag" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
