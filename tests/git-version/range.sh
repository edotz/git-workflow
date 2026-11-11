#!/usr/bin/env bash
# Purpose: Check version_next and version_notes_args on throwaway repositories: the commits after the latest tag decide,
#          wherever the tag sits (outside the component path, on the first commit, older than a pre-release), a
#          component without a tag counts its whole history, and only feat, fix, perf and breaking commits of the
#          component make a release and appear in the notes (D86).
# Usage: bash tests/git-version/range.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
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

repo=""
n=0

# A fresh repository with the components a and b and a baseline tag a/v1.0.0 on a commit that touches only b.
fresh() {
  repo="${work}/r${n}"
  n=$((n + 1))
  git init -q -b master "$repo"
  git -C "$repo" config user.name t
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config core.hooksPath /dev/null
  mkdir -p "${repo}/.agentic-os" "${repo}/packages/a" "${repo}/packages/b"
  printf 'components:\n  - name: a\n    paths: ["packages/a"]\n  - name: b\n    paths: ["packages/b"]\n' > "${repo}/components.yaml"
  echo 1 > "${repo}/packages/a/f"
  echo 1 > "${repo}/packages/b/f"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "feat(a): first"
  echo 2 > "${repo}/packages/b/f"
  git -C "$repo" commit -q -am "fix(b): other"
  git -C "$repo" tag a/v1.0.0
  return 0
}

# Add one commit that touches a path of the repository; the optional third argument is the body.
add() {
  local file="$1" subject="$2" body="${3:-}"
  mkdir -p "${repo}/${file%/*}"
  echo "$subject" >> "${repo}/${file}"
  git -C "$repo" add .
  if [[ -n "$body" ]]; then
    git -C "$repo" commit -q -m "$subject" -m "$body"
  else
    git -C "$repo" commit -q -m "$subject"
  fi
}

# Run version_next in the repository; sets OUT (stdout) and RC.
OUT=""
RC=0
next() {
  RC=0
  OUT="$(cd "$repo" && env -u GH_TOKEN PROJECT_ROOT="$repo" PLUGIN_ROOT="$PLUGIN_ROOT" PLUGIN_LIB="$PLUGIN_LIB" bash -c '
    set -euo pipefail
    source "${BU_ROOT}/lib/core.sh"
    source "${PLUGIN_LIB}/version.sh"
    component_load "${PROJECT_ROOT}/components.yaml"
    version_next "$@"
  ' next "$@" 2>/dev/null)" || RC=$?
}

# Run version_notes_args and git-cliff in the repository; sets OUT (the notes) and RC.
notes() {
  RC=0
  OUT="$(cd "$repo" && env -u GH_TOKEN PROJECT_ROOT="$repo" PLUGIN_ROOT="$PLUGIN_ROOT" PLUGIN_LIB="$PLUGIN_LIB" bash -c '
    set -euo pipefail
    source "${BU_ROOT}/lib/core.sh"
    source "${PLUGIN_LIB}/version.sh"
    component_load "${PROJECT_ROOT}/components.yaml"
    version_notes_args "$@"
    version_cliff "${VERSION_NOTES_ARGS[@]}" --strip header
  ' notes "$@" 2>/dev/null)" || RC=$?
}

fresh
next a
ok=no
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then ok=yes; fi
case_result "a baseline tag on a commit outside the component path and nothing after it: no release" "$ok"

add packages/a/ci.txt "ci: change a workflow in a"
add packages/a/docs.txt "docs(a): explain"
add packages/a/inner.txt "refactor(a): inner change"
add packages/a/deps.txt "chore(deps): bump x"
next a
ok=no
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then ok=yes; fi
case_result "ci, docs, refactor and chore commits in the path: no release" "$ok"

add packages/b/only.txt "feat(b): a feature of b"
next a
ok=no
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then ok=yes; fi
case_result "a feat in another component: no release of a" "$ok"

add packages/a/fix.txt "fix(a): a fix"
next a
ok=no
if [[ "$RC" -eq 0 && "$OUT" == "1.0.1" ]]; then ok=yes; fi
case_result "a fix in the path: patch 1.0.1" "$ok"

add packages/a/feat.txt "feat(a): a feature"
next a
ok=no
if [[ "$RC" -eq 0 && "$OUT" == "1.1.0" ]]; then ok=yes; fi
case_result "a feat in the path: minor 1.1.0" "$ok"

add packages/a/breaking.txt "refactor(a)!: drop the old api"
next a
ok=no
if [[ "$RC" -eq 0 && "$OUT" == "2.0.0" ]]; then ok=yes; fi
case_result "a breaking commit with an exclamation mark: major 2.0.0" "$ok"

fresh
add packages/a/footer.txt "chore(a): tidy" "BREAKING CHANGE: the api changed"
next a
ok=no
if [[ "$RC" -eq 0 && "$OUT" == "2.0.0" ]]; then ok=yes; fi
case_result "a breaking change footer on a chore commit: major 2.0.0" "$ok"

fresh
add packages/a/perf.txt "perf(a): faster"
next a
ok=no
if [[ "$RC" -eq 0 && "$OUT" == "1.0.1" ]]; then ok=yes; fi
case_result "a perf commit in the path: patch 1.0.1" "$ok"

fresh
add packages/a/feat.txt "feat(a): a feature"
next a rc
ok=no
if [[ "$RC" -eq 0 && "$OUT" == "1.1.0-rc.1" ]]; then ok=yes; fi
case_result "a feat with the channel rc: 1.1.0-rc.1" "$ok"

git -C "$repo" tag a/v1.1.0-rc.1
next a rc
ok=no
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then ok=yes; fi
case_result "nothing after the pre-release tag: no change" "$ok"

add packages/a/fix.txt "fix(a): a fix after the pre-release"
next a rc
ok=no
if [[ "$RC" -eq 0 && "$OUT" == "1.1.0-rc.2" ]]; then ok=yes; fi
case_result "a fix after the pre-release tag: 1.1.0-rc.2" "$ok"

fresh
echo 9 > "${repo}/packages/a/later"
git -C "$repo" tag -d a/v1.0.0 > /dev/null
next a
ok=no
if [[ "$RC" -eq 0 && "$OUT" == "0.1.0" ]]; then ok=yes; fi
case_result "a component without a tag counts its whole history" "$ok"

fresh
add packages/a/feat.txt "feat(a): a feature before the pre-release"
git -C "$repo" tag a/v1.1.0-rc.1
add packages/a/fix.txt "fix(a): a fix after the pre-release"
next a
ok=no
if [[ "$RC" -eq 0 && "$OUT" == "1.1.0" ]]; then ok=yes; fi
case_result "the stable release after a pre-release counts from the older stable tag: 1.1.0" "$ok"

fresh
add packages/a/fix.txt "fix(a): a fix for the notes"
add packages/a/ci.txt "ci: noise in a"
notes a a/v1.0.1 new 1.0.1
ok=no
if [[ "$RC" -eq 0 && "$OUT" == *"A fix for the notes"* && "$OUT" != *"First"* && "$OUT" != *"oise"* ]]; then ok=yes; fi
case_result "the notes of a new release hold the fix, not the commit before the baseline tag and not the ci commit" "$ok"

git -C "$repo" tag a/v1.0.1
add packages/a/feat.txt "feat(a): a later feature"
notes a a/v1.0.1 latest 1.0.1
ok=no
if [[ "$RC" -eq 0 && "$OUT" == *"A fix for the notes"* && "$OUT" != *"later feature"* && "$OUT" != *"First"* ]]; then ok=yes; fi
case_result "the notes of an existing tag hold the commits since the previous tag only" "$ok"

repo="${work}/root"
git init -q -b master "$repo"
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.com
git -C "$repo" config core.hooksPath /dev/null
mkdir -p "${repo}/.agentic-os" "${repo}/packages/a"
printf 'components:\n  - name: a\n    paths: ["packages/a"]\n' > "${repo}/components.yaml"
echo 1 > "${repo}/packages/a/f"
git -C "$repo" add .
git -C "$repo" commit -q -m "feat(a): first and only"
echo 2 > "${repo}/packages/a/CHANGELOG"
git -C "$repo" add .
git -C "$repo" commit -q -m "chore(a): release a/v1.0.0"
git -C "$repo" tag a/v1.0.0
notes a a/v1.0.0 latest 1.0.0
ok=no
if [[ "$RC" -eq 0 && "$OUT" == *"First and only"* ]]; then ok=yes; fi
case_result "the notes of the first tag, which has no previous tag, hold the commits before its release commit" "$ok"

exit "$failed"
