#!/usr/bin/env bash
# Purpose: Check bin/lib/remote.sh on a throwaway repository: the three URL forms, the missing remote and both identity values.
# Usage: bash tests/git-remote/run.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
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
mkdir "${repo}/.agentic-os"

# Run one library function in the throwaway repository, with no global git config.
run_remote() {
  (
    cd "$repo"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    bash -c 'set -euo pipefail; source "${BU_ROOT}/lib/core.sh"; source "${PLUGIN_ROOT}/bin/lib/remote.sh"; "$@"' _ "$@" 2>&1
  )
}

check_slug() {
  local label="$1" url="$2" want="$3" rc=0 out ok=no
  git -C "$repo" remote remove origin 2>/dev/null || true
  git -C "$repo" remote add origin "$url"
  out="$(run_remote remote_slug)" || rc=$?
  if [[ "$rc" -eq 0 && "$out" == "$want" ]]; then ok=yes; fi
  case_result "$label" "$ok"
}

check_slug "the ssh form git@host:owner/name.git" "git@github.com:acme/widget.git" "acme/widget"
check_slug "the ssh form without .git" "git@github.com:acme/widget" "acme/widget"
check_slug "the https form with .git" "https://github.com/acme/widget.git" "acme/widget"
check_slug "the https form without .git" "https://github.com/acme/widget" "acme/widget"
check_slug "a query string is dropped" "https://github.com/acme/widget?x=1" "acme/widget"

git -C "$repo" remote add upstream "https://example.org/other/tool.git"
rc=0
out="$(run_remote remote_slug upstream)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == "other/tool" ]]; then ok=yes; fi
case_result "a named remote is read instead of origin" "$ok"

git -C "$repo" remote remove upstream
git -C "$repo" remote remove origin
rc=0
out="$(run_remote remote_slug)" || rc=$?
ok=no
if [[ "$rc" -eq 4 && "$out" == *"no remote origin"* ]]; then ok=yes; fi
case_result "a missing remote dies with exit 4 and a message" "$ok"

git -C "$repo" remote add origin "${work}/not-a-slug"
rc=0
out="$(run_remote remote_slug)" || rc=$?
ok=no
if [[ "$rc" -eq 3 && "$out" == *"has no owner/name"* ]]; then ok=yes; fi
case_result "a URL without owner/name dies with exit 3 and a message" "$ok"

rc=0
out="$(run_remote remote_identity name)" || rc=$?
ok=no
if [[ "$rc" -eq 3 && "$out" == *"user.name is not set"* ]]; then ok=yes; fi
case_result "an unset user.name dies naming the key" "$ok"

rc=0
out="$(run_remote remote_identity email)" || rc=$?
ok=no
if [[ "$rc" -eq 3 && "$out" == *"user.email is not set"* ]]; then ok=yes; fi
case_result "an unset user.email dies naming the key" "$ok"

git -C "$repo" config user.name "   "
rc=0
out="$(run_remote remote_identity name)" || rc=$?
ok=no
if [[ "$rc" -eq 3 && "$out" == *"user.name is not set"* ]]; then ok=yes; fi
case_result "a whitespace-only user.name counts as unset" "$ok"

git -C "$repo" config user.name "Jane Doe"
git -C "$repo" config user.email "jane@example.com"
rc=0
out="$(run_remote remote_identity name)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == "Jane Doe" ]]; then ok=yes; fi
case_result "remote_identity name gives user.name" "$ok"

rc=0
out="$(run_remote remote_identity email)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == "jane@example.com" ]]; then ok=yes; fi
case_result "remote_identity email gives user.email" "$ok"

rc=0
out="$(run_remote remote_identity phone)" || rc=$?
ok=no
if [[ "$rc" -eq 2 ]]; then ok=yes; fi
case_result "another identity key is a usage error" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
