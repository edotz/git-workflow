#!/usr/bin/env bash
# Purpose: Check that a clone with the pre-push shim still pushes in the tool image: the shim runs agentic-os, which
#          the image lacks, so a push through tool_run needs -c core.hooksPath=/dev/null as release, pr, promote and
#          split pass it, while a push on the host still runs the hook.
# Usage: bash tests/git-shims/push.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it); needs docker for the tool image
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
cd "$root"

source "${BU_ROOT}/lib/core.sh"
source "${PLUGIN_LIB}/tool.sh"

shims="${root}/bin/modules/git/shims.sh"
require_file "$shims" "the shims command"
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

# The tool image mounts only the repository around the working directory, so the bare remote lies inside the clone.
repo="${work}/r"
remote="${repo}/.remote.git"
marker="${work}/hook-ran"

git init -q --template= -b master "$repo"
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.com
git init -q --bare -b master "$remote"
git -C "$repo" remote add origin "$remote"
mkdir "${repo}/.agentic-os"
touch "${repo}/.agentic-os/.keep"
git -C "$repo" add .agentic-os/.keep
git -C "$repo" -c core.hooksPath=/dev/null commit -q -m "chore: base"

(cd "$repo" && env -u GH_TOKEN bash "$shims" >/dev/null 2>&1) || true
case_result "the clone has an executable pre-push shim" "$([[ -x "${repo}/.git/hooks/pre-push" ]] && echo yes || echo no)"

mkdir "${work}/bin"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$marker" > "${work}/bin/agentic-os"
chmod +x "${work}/bin/agentic-os"

commit_file() {
  printf '%s\n' "$1" > "${repo}/$1"
  git -C "$repo" add "$1"
  git -C "$repo" -c core.hooksPath=/dev/null commit -q -m "chore: add $1"
}

remote_head() { git -C "$remote" rev-parse --verify -q refs/heads/master || echo none; }
local_head() { git -C "$repo" rev-parse HEAD; }

commit_file one
rc=0
(cd "$repo" && tool_run git push -q origin master >/dev/null 2>&1 </dev/null) || rc=$?
case_result "a push in the tool image without the override fails on the shim and sends nothing" "$([[ "$rc" -ne 0 && "$(remote_head)" == none ]] && echo yes || echo no)"

rc=0
(cd "$repo" && tool_run git -c core.hooksPath=/dev/null push -q origin master >/dev/null 2>&1 </dev/null) || rc=$?
case_result "a push in the tool image with core.hooksPath=/dev/null succeeds although the clone has the shim" "$([[ "$rc" -eq 0 && "$(remote_head)" == "$(local_head)" ]] && echo yes || echo no)"

git -C "$repo" tag v0.0.1
rc=0
(cd "$repo" && tool_run git -c core.hooksPath=/dev/null push -q origin refs/tags/v0.0.1 >/dev/null 2>&1 </dev/null) || rc=$?
case_result "a tag push in the tool image succeeds although the clone has the shim" "$([[ "$rc" -eq 0 ]] && git -C "$remote" rev-parse --verify -q refs/tags/v0.0.1 >/dev/null && echo yes || echo no)"

commit_file two
rc=0
(cd "$repo" && PATH="${work}/bin:${PATH}" git push -q origin master >/dev/null 2>&1 </dev/null) || rc=$?
case_result "a push on the host still runs the pre-push hook" "$([[ "$rc" -eq 0 && -e "$marker" && "$(remote_head)" == "$(local_head)" ]] && echo yes || echo no)"

exit "$failed"
