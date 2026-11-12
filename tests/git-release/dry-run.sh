#!/usr/bin/env bash
# Purpose: Check app git release on a throwaway repository: the dry run end to end, the refusals before any write.
# Usage: bash tests/git-release/dry-run.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail
# The framework takes an exported PROJECT_ROOT before the working directory; the throwaway repository is the working directory.
unset PROJECT_ROOT AOS_ROOT SESSION_DIR AOS_TIER_CHAIN

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
release="${root}/bin/modules/git/release.sh"
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
mkdir "${repo}/.agentic-os"
printf '{"name":"o","version":"1.0.0"}\n' > "${repo}/package.json"
printf 'components:\n  - name: object\n    paths: ["."]\n    version_files: [package.json]\n' > "${repo}/components.yaml"
git -C "$repo" add .
git -C "$repo" commit -q -m "chore: init"
git -C "$repo" tag v1.0.0
echo a > "${repo}/a"
git -C "$repo" add a
git -C "$repo" commit -q -m "feat: add a"

run_release() {
  (cd "$repo" && env -u GH_TOKEN TOKEN_SERVICE_URL=http://127.0.0.1:9 bash "$release" "$@" 2>&1)
}

out=""
rc=0
out="$(run_release --dry-run)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"1.1.0"* && "$out" == *"v1.1.0"* && "$out" == *"package.json"* ]]; then ok=yes; fi
case_result "the dry run prints the next version, the tag and the files" "$ok"

ok=no
if [[ "$out" == *"Features"* && "$out" == *"Add a"* ]]; then ok=yes; fi
case_result "the dry run prints the notes of git-cliff" "$ok"

ok=no
if [[ -z "$(git -C "$repo" status --porcelain)" && "$(git -C "$repo" tag)" == "v1.0.0" \
  && "$(git -C "$repo" rev-list --count HEAD)" == "2" && "$(cat "${repo}/package.json")" == *'"version":"1.0.0"'* ]]; then
  ok=yes
fi
case_result "the dry run changes nothing: clean tree, one tag, two commits, version 1.0.0" "$ok"

rc=0
out="$(run_release)" || rc=$?
ok=no
if [[ "$rc" -eq 2 ]]; then ok=yes; fi
case_result "neither --dry-run nor --apply is a usage error" "$ok"

rc=0
out="$(run_release --dry-run --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 2 ]]; then ok=yes; fi
case_result "both --dry-run and --apply is a usage error" "$ok"

rc=0
out="$(run_release --dry-run --pre rc)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"1.1.0-rc.1"* ]]; then ok=yes; fi
case_result "--pre rc starts the pre-release line" "$ok"

echo b >> "${repo}/a"
rc=0
out="$(run_release --apply)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"uncommitted changes"* && "$out" != *"unreachable"* ]]; then ok=yes; fi
case_result "apply refuses a dirty tree before it fetches a token" "$ok"
git -C "$repo" checkout -q -- a

git -C "$repo" commit -q --allow-empty -m "not conventional"
rc=0
out="$(run_release --dry-run)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"minimum check is red"* ]]; then ok=yes; fi
case_result "a red minimum check refuses the release" "$ok"

# The release commit runs in the tool container without the hooks of the repository: a hook that needs the host
# (agentic-os) fails there, and core.hooksPath=/dev/null lets the commit through.
git -C "$repo" config --unset core.hooksPath
mkdir -p "${repo}/.git/hooks"
printf '#!/bin/sh\nexit 1\n' > "${repo}/.git/hooks/pre-commit"
chmod +x "${repo}/.git/hooks/pre-commit"
git -C "$repo" reset -q --hard HEAD~1
echo c > "${repo}/c"
git -C "$repo" add c

tool_git() {
  (cd "$repo" && PLUGIN_ROOT="$root" PLUGIN_LIB="${root}/bin/lib" bash -c 'source "${BU_ROOT}/lib/core.sh"; source "${PLUGIN_ROOT}/bin/lib/tool.sh"; tool_run git "$@" </dev/null' _ "$@" >/dev/null 2>&1)
}

rc=0
tool_git -c user.name=t -c user.email=t@example.com commit -q -m "feat: c" || rc=$?
ok=no
if [[ "$rc" -ne 0 ]]; then ok=yes; fi
case_result "a failing repository hook blocks a commit in the container" "$ok"

rc=0
tool_git -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null commit -q -m "feat: c" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$(git -C "$repo" log -1 --format=%s)" == "feat: c" ]]; then ok=yes; fi
case_result "core.hooksPath=/dev/null lets the release commit through" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
