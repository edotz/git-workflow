#!/usr/bin/env bash
# Purpose: Check app git shims on a throwaway repository: install into the default hooks directory, a second run
#          that changes nothing, a stale shim, --check, a worktree, core.hooksPath (relative, with a foreign hook
#          that must stay) and a directory that is no repository.
# Usage: bash tests/git-shims/run.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
shims="${root}/bin/modules/git/shims.sh"
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

repo="${work}/r"
git init -q --template= -b master "$repo"
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.com
mkdir "${repo}/.agentic-os"
touch "${repo}/.agentic-os/.keep"
git -C "$repo" add .agentic-os/.keep
git -C "$repo" -c core.hooksPath=/dev/null commit -q -m "chore: base"

run_shims() {
  local dir="$1"
  shift
  (cd "$dir" && env -u GH_TOKEN bash "$shims" "$@" 2>&1)
}

keys="$(grep -c 'event:' "${root}/adapters/git/hooks/hooks.yaml")"

out="$(run_shims "$repo" || true)"
ok=yes
for hook in pre-commit commit-msg pre-push; do
  if [[ ! -x "${repo}/.git/hooks/${hook}" ]] || ! cmp -s "${root}/.git-templates/hooks/${hook}" "${repo}/.git/hooks/${hook}"; then ok=no; fi
done
case_result "installs one executable shim per mapped hook into .git/hooks (${keys} mapped)" "$ok"

out="$(run_shims "$repo" || true)"
case_result "a second run reports every shim current" "$([[ "$out" != *installed* && "$out" == *current* ]] && echo yes || echo no)"

printf '#!/bin/bash\n# agentic-os-hook: old\nexit 0\n' > "${repo}/.git/hooks/pre-push"
out="$(run_shims "$repo" --check || true)"
rc=0
(cd "$repo" && bash "$shims" --check >/dev/null 2>&1) || rc=$?
case_result "--check names a stale shim, exits 1 and changes nothing" "$([[ "$out" == *"pre-push: missing or stale"* && "$rc" -eq 1 ]] && grep -q "old" "${repo}/.git/hooks/pre-push" && echo yes || echo no)"

run_shims "$repo" >/dev/null || true
case_result "a run replaces the stale shim" "$(cmp -s "${root}/.git-templates/hooks/pre-push" "${repo}/.git/hooks/pre-push" && echo yes || echo no)"

git -C "$repo" worktree add -q "${work}/wt" -b feature
rm -f "${repo}/.git/hooks/commit-msg"
run_shims "${work}/wt" >/dev/null || true
case_result "a run inside a worktree writes into the common git dir" "$([[ -x "${repo}/.git/hooks/commit-msg" && -f "${work}/wt/.git" ]] && echo yes || echo no)"

git -C "$repo" config core.hooksPath .husky
mkdir "${repo}/.husky"
printf '#!/bin/sh\necho foreign\n' > "${repo}/.husky/pre-commit"
rc=0
out="$(run_shims "$repo")" || rc=$?
ok=yes
if ! grep -q foreign "${repo}/.husky/pre-commit"; then ok=no; fi
if [[ "$out" != *"pre-commit: conflict"* || "$rc" -ne 3 ]]; then ok=no; fi
if [[ ! -x "${repo}/.husky/commit-msg" || ! -x "${repo}/.husky/pre-push" ]]; then ok=no; fi
case_result "core.hooksPath is honoured; a foreign hook stays, is reported (exit 3) and the others are installed" "$ok"

mkdir "${work}/plain" "${work}/plain/.agentic-os"
rc=0
(cd "${work}/plain" && env -u GH_TOKEN bash "$shims" >/dev/null 2>&1) || rc=$?
case_result "outside a repository it exits 4" "$([[ "$rc" -eq 4 ]] && echo yes || echo no)"

exit "$failed"
