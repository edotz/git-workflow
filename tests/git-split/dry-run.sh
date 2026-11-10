#!/usr/bin/env bash
# Purpose: Check app git split --dry-run on a throwaway monorepo whose child repositories are bare repositories inside
#          its git directory (the https URL of the child is rewritten to them with url.<base>.insteadOf).
# Usage: bash tests/git-split/dry-run.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
split="${root}/bin/modules/git/split.sh"
failed=0

case_result() {
  if [[ "$2" == "yes" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failed=1
  fi
}

first_sha() {
  local sha=""
  if [[ "$1" =~ [0-9a-f]{40} ]]; then sha="${BASH_REMATCH[0]}"; fi
  printf '%s' "$sha"
}

work="$(mktemp -d)"
finish() { rm -rf "$work"; }
trap finish EXIT

repo="${work}/r"
kids="${repo}/.git/children"
git init -q -b master "$repo"
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.com
git -C "$repo" config core.hooksPath /dev/null
git -C "$repo" config "url.file://${kids}/.insteadOf" "https://github.com/"
mkdir "${repo}/.agentic-os"

git init -q --bare -b master "${kids}/own/web.git"
git init -q --bare -b master "${kids}/own/fresh.git"
git init -q --bare -b master "${kids}/own/lib.git"
old="${work}/old"
git init -q -b master "$old"
git -C "$old" config user.name t
git -C "$old" config user.email t@example.com
git -C "$old" config core.hooksPath /dev/null
echo legacy > "${old}/legacy.txt"
git -C "$old" add legacy.txt
git -C "$old" commit -q -m "chore: legacy child"
git -C "$old" push -q "${kids}/own/lib.git" master

cat > "${repo}/components.yaml" <<'YAML'
components:
  - name: web
    paths: [apps/web]
    split: "yes"
    owner: own
    repo: web
  - name: fresh
    paths: [apps/fresh]
    split: "yes"
    owner: own
    repo: fresh
  - name: lib
    paths: [packages/lib]
    split: "yes"
    owner: own
    repo: lib
  - name: broken
    paths: [apps/broken]
    split: "yes"
    owner: o
    repo: r
    host: "127.0.0.1:9"
  - name: nohist
    paths: [apps/nohist]
    split: "yes"
    owner: own
    repo: fresh
  - name: infra
    paths: [infra]
YAML
mkdir -p "${repo}/apps/web" "${repo}/apps/fresh" "${repo}/apps/broken" "${repo}/packages/lib" "${repo}/infra"
echo a1 > "${repo}/apps/web/a.txt"
echo f > "${repo}/apps/fresh/f.txt"
echo b > "${repo}/apps/broken/b.txt"
echo l > "${repo}/packages/lib/l.txt"
echo i > "${repo}/infra/i.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m "chore: init"

run_split() {
  (cd "$repo" && env -u PROJECT_ROOT -u AOS_ROOT -u SESSION_DIR -u AOS_TIER_CHAIN GIT_WORKFLOW_MAIN_BRANCH=master bash "$split" "$@" 2>&1)
}

rc=0
out="$(run_split web --dry-run)" || rc=$?
h1="$(first_sha "$out")"
if [[ "$rc" -ne 0 || -z "$h1" ]]; then
  echo "FAIL the first dry run of web did not print a split head (exit ${rc}): ${out}"
  exit 1
fi
git -C "$repo" push -q "${kids}/own/web.git" "${h1}:refs/heads/master"

echo a2 > "${repo}/apps/web/a.txt"
echo b > "${repo}/apps/web/b.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m "feat: web grows"

snap() {
  git -C "$repo" rev-parse HEAD
  git -C "$repo" status --porcelain
  git -C "$repo" for-each-ref
  git -C "${kids}/own/web.git" for-each-ref
  git -C "${kids}/own/lib.git" for-each-ref
  git -C "${kids}/own/fresh.git" for-each-ref
}
before="$(snap)"

rc=0
out="$(run_split web --dry-run)" || rc=$?
h2="$(first_sha "$out")"
ok=no
if [[ "$rc" -eq 0 && -n "$h2" && "$h2" != "$h1" \
  && "$(git -C "$repo" cat-file -t "$h2" 2>/dev/null)" == "commit" \
  && "$(git -C "$repo" ls-tree --name-only "$h2" | tr '\n' ' ')" == "a.txt b.txt " \
  && "$out" == *"fast-forward"* && "$out" == *"b.txt"* ]]; then ok=yes; fi
case_result "split head printed, with the ancestry and the tree difference of a related child" "$ok"

rc=0
out="$(run_split lib --dry-run)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"unrelated"* && "$out" == *"baseline"* && "$out" == *"legacy.txt"* ]]; then ok=yes; fi
case_result "unrelated child needs a baseline" "$ok"

rc=0
out="$(run_split infra --dry-run)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"skipped"* && "$out" != *"split head"* ]]; then ok=yes; fi
case_result "unsplit component skipped" "$ok"

rc=0
out="$(run_split broken --dry-run)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"failed read"* && "$out" != *"absent"* ]]; then ok=yes; fi
case_result "failed read reported as a failed read" "$ok"

rc=0
out="$(run_split fresh --dry-run)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"absent on the child"* ]]; then ok=yes; fi
case_result "an absent child ref is told from a failed read" "$ok"

rc=0
out="$(run_split ghost --dry-run)" || rc=$?
ok=no
if [[ "$rc" -eq 4 && "$out" == *"not declared"* && "$out" != *"skipped"* ]]; then ok=yes; fi
case_result "unknown component is a not-found error" "$ok"

rc=0
out="$(run_split nohist --dry-run)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" != *"split head"* && "$out" == *"no history"* ]]; then ok=yes; fi
case_result "component without history fails and prints no empty split head" "$ok"

real_docker="$(command -v docker)"
mkdir "${work}/stub"
cat > "${work}/stub/docker" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == "\${STUB_FAIL_ON:-}" ]]; then exit "\${STUB_FAIL_RC:-1}"; fi
done
exec "${real_docker}" "\$@"
STUB
chmod +x "${work}/stub/docker"

rc=0
out="$(PATH="${work}/stub:${PATH}" STUB_FAIL_ON=merge-base STUB_FAIL_RC=128 run_split web --dry-run)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"merge-base answered with 128"* && "$out" != *"tree difference"* && "$out" == *"failed"* ]]; then ok=yes; fi
case_result "a failed ancestry read counts as a failed component and prints no tree difference" "$ok"

rc=0
out="$(PATH="${work}/stub:${PATH}" STUB_FAIL_ON=diff run_split web --dry-run)" || rc=$?
ok=no
if [[ "$rc" -ne 0 && "$out" == *"git diff failed"* && "$out" != *"tree difference: none"* && "$out" == *"failed"* ]]; then ok=yes; fi
case_result "a failed diff counts as a failed component and prints no tree difference none" "$ok"

after="$(snap)"
ok=no
if [[ "$before" == "$after" && -z "$(git -C "$repo" status --porcelain)" ]]; then ok=yes; fi
case_result "tree and remote unchanged" "$ok"

rc=0
out="$(run_split web)" || rc=$?
ok=no
if [[ "$rc" -eq 2 ]]; then ok=yes; fi
case_result "neither flag is a usage error" "$ok"

rc=0
out="$(run_split web --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 2 && "$out" == *"not built"* ]]; then ok=yes; fi
case_result "--apply is a usage error until it is built" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
