#!/usr/bin/env bash
# Purpose: Check app git release --dry-run on fixture repositories with several components and with a single root component.
# Usage: bash tests/git-release/multi.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it); needs docker for the tool image
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
# Not covered: --apply needs the github.com origin and the token service, the sandbox pilot proves it (D66)
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
: "${BU_ROOT:?BU_ROOT must be set}"
cd "$root"
source "${BU_ROOT}/lib/core.sh"

release="${root}/bin/modules/git/release.sh"
failed=0

require_command git
require_command docker "install Docker: the dry run runs in the tool image"
if [[ ! -f "$release" ]]; then
  die_with "$BU_EXIT_CONFIG" "multi: ${release} does not exist"
fi

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
register_cleanup finish

new_repo() {
  git init -q -b master "$1"
  git -C "$1" config user.name t
  git -C "$1" config user.email t@example.com
  git -C "$1" config core.hooksPath /dev/null
  mkdir "${1}/.agentic-os"
  return 0
}

run_release() {
  (cd "$1" && env -u GH_TOKEN -u PROJECT_ROOT -u AOS_ROOT -u SESSION_DIR -u AOS_TIER_CHAIN TOKEN_SERVICE_URL=http://127.0.0.1:9 bash "$release" --dry-run 2>&1)
}

# The state a dry run must leave as it found it: HEAD, the tags and the status of the working tree.
snapshot() {
  printf '%s|%s|%s' "$(git -C "$1" rev-parse HEAD)" "$(git -C "$1" tag | tr '\n' ' ')" "$(git -C "$1" status --porcelain)"
}

# The lines of one component in the output: from its header to the next header.
section() {
  local text="${1#*"[release ${2}]"}"
  printf '%s' "${text%%"[release "*}"
}

multi="${work}/multi"
new_repo "$multi"
mkdir "${multi}/api" "${multi}/web"
printf '{"name":"api","version":"1.0.0"}\n' > "${multi}/api/package.json"
printf '{"name":"web","version":"2.0.0"}\n' > "${multi}/web/package.json"
cat > "${multi}/components.yaml" <<'YAML'
components:
  - name: api
    paths: [api]
    version_files: [api/package.json]
  - name: web
    paths: [web]
    version_files: [web/package.json]
YAML
git -C "$multi" add .
git -C "$multi" commit -q -m "chore: init"
git -C "$multi" tag api/v1.0.0
git -C "$multi" tag web/v2.0.0
echo a > "${multi}/api/a"
git -C "$multi" add api/a
git -C "$multi" commit -q -m "feat: add a"
echo w > "${multi}/web/w"
git -C "$multi" add web/w
git -C "$multi" commit -q -m "fix: repair w"
before_multi="$(snapshot "$multi")"

rc=0
out="$(run_release "$multi")" || rc=$?
api="$(section "$out" api)"
web="$(section "$out" web)"
ok=no
if [[ "$rc" -eq 0 && "$out" == *"[release api]"* && "$out" == *"[release web]"* \
  && "$api" == *"1.1.0"* && "$api" == *"api/v1.1.0"* && "$api" == *"api/package.json"* \
  && "$web" == *"2.0.1"* && "$web" == *"web/v2.0.1"* && "$web" == *"web/package.json"* ]]; then
  ok=yes
fi
case_result "both components are listed with their next version, tag and files" "$ok"
after_multi_both="$(snapshot "$multi")"

# Both components now sit on a release commit and a tag of their own, as a release leaves them: the version files
# hold the tagged version. Only api changes after it.
printf '{"name":"api","version":"1.1.0"}\n' > "${multi}/api/package.json"
printf '{"name":"web","version":"2.0.1"}\n' > "${multi}/web/package.json"
git -C "$multi" add api/package.json web/package.json
git -C "$multi" commit -q -m "chore: release api and web"
git -C "$multi" tag api/v1.1.0
git -C "$multi" tag web/v2.0.1
echo b >> "${multi}/api/a"
git -C "$multi" add api/a
git -C "$multi" commit -q -m "feat: extend a"
before_unchanged="$(snapshot "$multi")"

rc=0
out="$(run_release "$multi")" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"[release api]"* && "$out" == *"api/v1.2.0"* \
  && "$out" != *"[release web]"* && "$out" != *"web/v"* && "$out" != *"web/package.json"* ]]; then
  ok=yes
fi
case_result "a component whose paths did not change is not listed" "$ok"
after_unchanged="$(snapshot "$multi")"

single="${work}/single"
new_repo "$single"
printf '{"name":"o","version":"1.0.0"}\n' > "${single}/package.json"
printf 'components:\n  - name: object\n    paths: ["."]\n    version_files: [package.json]\n' > "${single}/components.yaml"
git -C "$single" add .
git -C "$single" commit -q -m "chore: init"
git -C "$single" tag v1.0.0
echo a > "${single}/a"
git -C "$single" add a
git -C "$single" commit -q -m "feat: add a"
before_single="$(snapshot "$single")"

rc=0
out="$(run_release "$single")" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"[release object]"* && "$out" == *"1.1.0"* && "$out" == *"v1.1.0"* \
  && "$out" == *"package.json"* && "$out" != *"/v1.1.0"* ]]; then
  ok=yes
fi
case_result "the single root component is listed with its next version, tag and files" "$ok"
after_single="$(snapshot "$single")"

ok=no
if [[ -z "$(git -C "$multi" status --porcelain)" && -z "$(git -C "$single" status --porcelain)" \
  && "$before_multi" == "$after_multi_both" && "$before_unchanged" == "$after_unchanged" \
  && "$before_single" == "$after_single" ]]; then
  ok=yes
fi
case_result "the tree is clean afterwards and HEAD, the tags and the files are unchanged" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
