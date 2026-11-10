#!/usr/bin/env bash
# Purpose: Check app git split --apply on a throwaway monorepo whose child repositories are bare repositories inside
#          its git directory (the https URL of the child is rewritten to them with url.<base>.insteadOf): the push of
#          the split head and the component tags to the branch of the monorepo, the baseline of an unrelated child
#          (legacy/pre-split, --confirm, lease), the refusals, and a component with two paths. gh and curl are stubs so
#          that the token request is counted; the tool image runs git and splitsh-lite.
# Usage: bash tests/git-split/apply.sh
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

stubs="${work}/stubs"
calls="${work}/calls.log"
mkdir "$stubs"
: > "$calls"
cat > "${stubs}/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" ]]; then
  echo "stub-developer-token"
  exit 0
fi
exit 1
STUB
cat > "${stubs}/curl" <<STUB
#!/usr/bin/env bash
cat >/dev/null
echo "token-request" >> "${calls}"
printf '{"token":"stub-installation-token"}\n200'
STUB
chmod +x "${stubs}/gh" "${stubs}/curl"

repo="${work}/r"
kids="${repo}/.git/children"
git init -q -b master "$repo"
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.com
git -C "$repo" config core.hooksPath /dev/null
git -C "$repo" config "url.file://${kids}/.insteadOf" "https://github.com/"
mkdir "${repo}/.agentic-os"

git init -q --bare -b master "${kids}/own/web.git"
git init -q --bare -b master "${kids}/own/lib.git"
git init -q --bare -b master "${kids}/own/multi.git"
git init -q --bare -b master "${kids}/own/an.git"
git init -q --bare -b trunk "${kids}/own/tr.git"
git init -q --bare -b develop "${kids}/own/cl.git"

old="${work}/old"
git init -q -b master "$old"
git -C "$old" config user.name t
git -C "$old" config user.email t@example.com
git -C "$old" config core.hooksPath /dev/null
echo legacy > "${old}/legacy.txt"
git -C "$old" add legacy.txt
git -C "$old" commit -q -m "chore: legacy child"
git -C "$old" push -q "${kids}/own/lib.git" master
git -C "$old" push -q "${kids}/own/cl.git" master:develop
old_lib="$(git -C "${kids}/own/lib.git" rev-parse refs/heads/master)"

cat > "${repo}/components.yaml" <<'YAML'
components:
  - name: web
    paths: [apps/web]
    split: "yes"
    owner: own
    repo: web
  - name: lib
    paths: [packages/lib]
    split: "yes"
    owner: own
    repo: lib
  - name: multi
    paths: [apps/m1, apps/m2]
    split: "yes"
    owner: own
    repo: multi
  - name: tr
    paths: [apps/tr]
    split: "yes"
    owner: own
    repo: tr
  - name: cl
    paths: [apps/cl]
    split: "yes"
    owner: own
    repo: cl
  - name: an
    paths: [apps/an]
    split: "yes"
    owner: own
    repo: an
  - name: infra
    paths: [infra]
YAML
mkdir -p "${repo}/apps/web" "${repo}/packages/lib" "${repo}/apps/m1" "${repo}/apps/m2" "${repo}/apps/tr" "${repo}/apps/cl" "${repo}/apps/an" "${repo}/infra"
echo a > "${repo}/apps/web/a.txt"
echo l > "${repo}/packages/lib/l.txt"
echo x > "${repo}/apps/m1/x.txt"
echo y > "${repo}/apps/m2/y.txt"
echo t > "${repo}/apps/tr/t.txt"
echo c > "${repo}/apps/cl/c.txt"
echo n > "${repo}/apps/an/n.txt"
echo i > "${repo}/infra/i.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m "chore: init"
git -C "$repo" tag web/v1.0.0
git -C "$repo" tag an/v1.0.0
echo b > "${repo}/apps/web/b.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m "feat: web grows"
git -C "$repo" tag web/v1.1.0

branch=master

run_split() {
  (cd "$repo" && env -u PROJECT_ROOT -u AOS_ROOT -u SESSION_DIR -u AOS_TIER_CHAIN -u GH_TOKEN \
    PATH="${stubs}:${PATH}" GIT_WORKFLOW_MAIN_BRANCH="$branch" bash "$split" "$@" 2>&1)
}

requests() {
  local n=0 line
  while IFS= read -r line; do
    n=$((n + 1))
  done < "$calls"
  printf '%s' "$n"
}

child() { printf '%s/own/%s.git' "$kids" "$1"; }

refs() { git -C "$(child "$1")" for-each-ref --format='%(refname)'; }

tree() { git -C "$(child "$1")" ls-tree --name-only "$2" | tr '\n' ' '; }

# 1 and 2: the split head and the component tags reach an empty child, and nothing else does
rc=0
out="$(run_split web --apply)" || rc=$?
h1="$(first_sha "$out")"
web_master="$(git -C "$(child web)" rev-parse refs/heads/master 2>/dev/null || true)"
web_v10="$(git -C "$(child web)" rev-parse refs/tags/v1.0.0 2>/dev/null || true)"
web_v11="$(git -C "$(child web)" rev-parse refs/tags/v1.1.0 2>/dev/null || true)"
ok=no
if [[ "$rc" -eq 0 && -n "$h1" && "$web_master" == "$h1" && "$web_v11" == "$h1" && -n "$web_v10" \
  && "$(tree web refs/tags/v1.0.0)" == "a.txt " && "$(tree web refs/heads/master)" == "a.txt b.txt " ]]; then ok=yes; fi
case_result "the split head and the component tags reach an empty child as vX.Y.Z" "$ok"

ok=no
if [[ "$(refs web | tr '\n' ' ')" == "refs/heads/master refs/tags/v1.0.0 refs/tags/v1.1.0 " ]]; then ok=yes; fi
case_result "the child gets the branch of the monorepo and the component tags and no other ref" "$ok"

# 3: the child is at the split head and has every tag
requests_before="$(requests)"
snap_before="$(refs web; git -C "$(child web)" rev-parse refs/heads/master)"
rc=0
out="$(run_split web --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$out" == *"nothing to apply"* && "$(requests)" == "$requests_before" \
  && "$(refs web; git -C "$(child web)" rev-parse refs/heads/master)" == "$snap_before" ]]; then ok=yes; fi
case_result "an up-to-date child is left alone, the second apply does nothing and asks for no token" "$ok"

# 4: a child that is behind receives a fast-forward without force and a new tag
echo a2 > "${repo}/apps/web/a.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m "feat: web changes"
git -C "$repo" tag web/v1.2.0
rc=0
out="$(run_split web --apply)" || rc=$?
h2="$(first_sha "$out")"
ok=no
if [[ "$rc" -eq 0 && -n "$h2" && "$h2" != "$h1" \
  && "$(git -C "$(child web)" rev-parse refs/heads/master)" == "$h2" \
  && "$(git -C "$(child web)" rev-parse "refs/tags/v1.2.0^{commit}")" == "$h2" \
  && "$(git -C "$(child web)" rev-parse refs/tags/v1.1.0)" == "$h1" \
  && -z "$(git -C "$(child web)" tag --list 'legacy/*')" ]] \
  && git -C "$(child web)" merge-base --is-ancestor "$h1" "$h2"; then ok=yes; fi
case_result "a child that is behind gets a fast-forward and the new tag, the old tag stays" "$ok"

# 5 and 6: the unrelated child is refused without the confirmation, and with a wrong one
requests_before="$(requests)"
rc=0
out="$(run_split lib --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 2 && "$out" == *"--confirm own/lib"* \
  && "$(git -C "$(child lib)" rev-parse refs/heads/master)" == "$old_lib" && "$(requests)" == "$requests_before" ]]; then ok=yes; fi
case_result "an unrelated child is refused without --confirm, nothing is pushed and no token is asked" "$ok"

rc=0
out="$(run_split lib --apply --confirm own/web)" || rc=$?
ok=no
if [[ "$rc" -eq 2 && "$out" == *"names own/web"* && "$(git -C "$(child lib)" rev-parse refs/heads/master)" == "$old_lib" ]]; then ok=yes; fi
case_result "--confirm with the name of another child is refused" "$ok"

# 7 and 8: the baseline replaces the unrelated child and keeps its old head
rc=0
out="$(run_split lib --apply --confirm own/lib)" || rc=$?
lib_master="$(git -C "$(child lib)" rev-parse refs/heads/master)"
ok=no
if [[ "$rc" -eq 0 && "$lib_master" != "$old_lib" && "$(tree lib refs/heads/master)" == "l.txt " ]]; then ok=yes; fi
case_result "an unrelated child is replaced by the split after --confirm" "$ok"

ok=no
if [[ "$(git -C "$(child lib)" rev-parse refs/tags/legacy/pre-split 2>/dev/null || true)" == "$old_lib" \
  && "$(tree lib refs/tags/legacy/pre-split)" == "legacy.txt " ]]; then ok=yes; fi
case_result "the old head of the baselined child is kept as legacy/pre-split" "$ok"

# 9 and 10: one child per apply, and a component with split no has no child
before="$(refs web; refs lib)"
rc=0
out="$(run_split --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 2 && "$out" == *"one child per run"* && "$(refs web; refs lib)" == "$before" ]]; then ok=yes; fi
case_result "--apply without a component is a usage error and pushes nothing" "$ok"

rc=0
out="$(run_split infra --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 2 && "$out" == *"split no"* ]]; then ok=yes; fi
case_result "a component with split no is refused" "$ok"

# 11: the branch is the setting of the monorepo, whatever its name
branch=trunk
rc=0
out="$(run_split tr --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$(refs tr | tr '\n' ' ')" == "refs/heads/trunk " && "$(tree tr refs/heads/trunk)" == "t.txt " ]]; then ok=yes; fi
case_result "a non-default setting reaches that branch of the child and no other" "$ok"

# 12: a child whose default branch is another one is refused with both names
branch=master
requests_before="$(requests)"
before="$(refs cl)"
rc=0
out="$(run_split cl --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 3 && "$out" == *"develop"* && "$out" == *"master"* && "$(refs cl)" == "$before" \
  && "$(requests)" == "$requests_before" ]]; then ok=yes; fi
case_result "a child with another default branch is refused naming both branches, nothing is pushed" "$ok"

# 13: a component with two paths: only the first one is the child, the other counts for change detection only (D76);
# splitsh-lite itself refuses two bare prefixes that land in the same directory
rc=0
out="$(run_split multi --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$(tree multi refs/heads/master)" == "x.txt " ]]; then ok=yes; fi
case_result "a component with two paths splits its first path only, the other path is not in the child" "$ok"

# 14: a child that holds an annotated tag at the right commit (the old release train made them) is not blocked
rc=0
out="$(run_split an --apply)" || rc=$?
an_commit="$(git -C "$(child an)" rev-parse "refs/tags/v1.0.0^{commit}" 2>/dev/null || true)"
if [[ "$rc" -ne 0 || -z "$an_commit" ]]; then
  echo "FAIL the first apply of an did not push its tag (exit ${rc}): ${out}"
  exit 1
fi
git -C "$(child an)" -c user.name=t -c user.email=t@example.com tag -f -a -m "annotated" v1.0.0 "$an_commit" > /dev/null
echo n2 > "${repo}/apps/an/n.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m "feat: an changes"
git -C "$repo" tag an/v1.1.0
rc=0
out="$(run_split an --apply)" || rc=$?
ok=no
if [[ "$rc" -eq 0 && "$(git -C "$(child an)" rev-parse "refs/tags/v1.1.0^{commit}" 2>/dev/null || true)" == "$(git -C "$(child an)" rev-parse refs/heads/master)" \
  && "$(git -C "$(child an)" cat-file -t refs/tags/v1.0.0)" == "tag" ]]; then ok=yes; fi
case_result "an annotated child tag at the right commit does not block the apply" "$ok"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
