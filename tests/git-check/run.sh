#!/usr/bin/env bash
# Purpose: Check app git check on a throwaway repository with two components: all green, a commit that is not
#          conventional, a failing declared check and an unknown component.
# Usage: bash tests/git-check/run.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
check="${root}/bin/modules/git/check.sh"
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
git init -q -b master "$repo"
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.com
git -C "$repo" config core.hooksPath /dev/null
mkdir "${repo}/.agentic-os" "${repo}/web" "${repo}/api"
echo 0 > "${repo}/web/f"
echo 0 > "${repo}/api/f"

write_components() {
  cat > "${repo}/components.yaml" <<EOF
components:
  - name: web
    paths: [web]
    checks: ["test -f web/f"]
  - name: api
    paths: [api]
    checks: ["$1"]
EOF
}

run_check() {
  (cd "$repo" && env -u GH_TOKEN bash "$check" "$@" 2>&1)
}

write_components "test -f api/f"
git -C "$repo" add -A
git -C "$repo" commit -q -m "chore: init"
echo 1 > "${repo}/web/f"
git -C "$repo" commit -q -am "feat: first change"

rc=0
out="$(run_check)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"web: ok"* && "$out" == *"api: ok"* ]]; then ok=yes; fi
case_result "every component green exits 0 and prints one ok line each" "$ok"

rc=0
out="$(run_check web)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"web: ok"* && "$out" != *"api:"* ]]; then ok=yes; fi
case_result "a named component checks that component only" "$ok"

echo 2 > "${repo}/web/f"
git -C "$repo" commit -q -am "this is not a conventional commit"

rc=0
out="$(run_check)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"web: failed"* && "$out" == *"this is not a conventional commit"* ]]; then ok=yes; fi
case_result "a commit that is not conventional turns the components red" "$ok"

git -C "$repo" tag web/v1.0.0
git -C "$repo" tag api/v1.0.0
write_components "exit 3"
git -C "$repo" commit -q -am "chore: declare a failing check"

rc=0
out="$(run_check)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"web: ok"* && "$out" == *"api: failed"* && "$out" == *"exit 3"* ]]; then ok=yes; fi
case_result "a failing declared check turns only its component red" "$ok"

rc=0
out="$(run_check web)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"web: ok"* ]]; then ok=yes; fi
case_result "a red component that is not named does not fail the run" "$ok"

rc=0
out="$(run_check nope)" || rc=$?
ok=no
if [[ "$rc" -eq 4 && "$out" == *"not declared"* && "$out" != *": ok"* ]]; then ok=yes; fi
case_result "an unknown component is refused with exit 4" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
