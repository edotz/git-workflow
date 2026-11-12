#!/usr/bin/env bash
# Purpose: Check app git changes on a throwaway repository: one line per changed file as state, a tab and the path, the
#          states staged, unstaged and untracked in that order, a file both staged and changed again listed twice, a
#          clean tree printing nothing, and a directory that is no repository refused.
# Usage: bash tests/git-changes/run.sh
# Arguments: none; BU_ROOT must be set (the framework shell sets it)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail
# The framework takes an exported PROJECT_ROOT before the working directory; the throwaway repository is the working directory.
unset PROJECT_ROOT AOS_ROOT SESSION_DIR AOS_TIER_CHAIN

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
export PLUGIN_ROOT="$root"
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"
: "${BU_ROOT:?BU_ROOT must point at the framework bin directory}"

changes="${root}/bin/modules/git/changes.sh"
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
mkdir -p "${repo}/.agentic-os"
git -C "$repo" init -q -b master
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.com
git -C "$repo" config core.hooksPath /dev/null
printf 'one\n' > "${repo}/base.txt"
printf 'one\n' > "${repo}/keep.txt"
git -C "$repo" add base.txt keep.txt
git -C "$repo" commit -q -m "chore: init"

# Run the command in the repository; sets OUT (stdout and stderr) and RC.
run_changes() {
  RC=0
  OUT="$(cd "$1" && bash "$changes" 2>&1)" || RC=$?
}

run_changes "$repo"
case_result "a clean tree prints nothing and exits 0" "$([[ "$RC" -eq 0 && -z "$OUT" ]] && echo yes || echo no)"

mkdir -p "${repo}/sub"
printf 'n\n' > "${repo}/sub/note.txt"
RC=0
OUT="$(cd "${repo}/sub" && PROJECT_ROOT="$repo" bash "$changes" 2>&1)" || RC=$?
case_result "started in a subdirectory it lists the paths relative to the project root" "$([[ "$RC" -eq 0 && "$OUT" == $'untracked\tsub/note.txt' ]] && echo yes || echo no)"
rm -rf "${repo}/sub"

printf 'new\n' > "${repo}/staged-new.txt"
git -C "$repo" add staged-new.txt
printf 'two\n' >> "${repo}/base.txt"
printf 'loose\n' > "${repo}/untracked.txt"
printf 'two\n' >> "${repo}/keep.txt"
git -C "$repo" add keep.txt
printf 'three\n' >> "${repo}/keep.txt"

run_changes "$repo"
expected=$'staged\tkeep.txt\nstaged\tstaged-new.txt\nunstaged\tbase.txt\nunstaged\tkeep.txt\nuntracked\tuntracked.txt'
case_result "staged, unstaged and untracked files are listed in that order, one per line" "$([[ "$RC" -eq 0 && "$OUT" == "$expected" ]] && echo yes || echo no)"

mkdir -p "${repo}/dir/sub"
printf 'x\n' > "${repo}/dir/sub/a.txt"
printf 'y\n' > "${repo}/dir/b.txt"
run_changes "$repo"
case_result "an untracked directory is listed by file, not by directory" "$([[ "$OUT" == *$'untracked\tdir/b.txt'* && "$OUT" == *$'untracked\tdir/sub/a.txt'* ]] && echo yes || echo no)"

git -C "$repo" add -A
git -C "$repo" commit -q -m "chore: commit the fixtures"

git -C "$repo" mv base.txt moved.txt
run_changes "$repo"
case_result "a staged rename lists the old and the new path" "$([[ "$OUT" == *$'staged\tbase.txt'* && "$OUT" == *$'staged\tmoved.txt'* ]] && echo yes || echo no)"
git -C "$repo" commit -q -m "chore: rename the base file"

printf 'x\n' > "${repo}/with space.txt"
printf 'x\n' > "${repo}/quote\"name.txt"
run_changes "$repo"
case_result "a path with a space is listed as it is" "$([[ "$OUT" == *$'untracked\twith space.txt'* ]] && echo yes || echo no)"
case_result "a path with a double quote is listed unquoted" "$([[ "$OUT" == *$'untracked\tquote"name.txt'* ]] && echo yes || echo no)"
rm -f "${repo}/with space.txt" "${repo}/quote\"name.txt"

rm "${repo}/keep.txt"
run_changes "$repo"
case_result "a deleted file is listed as unstaged" "$([[ "$OUT" == $'unstaged\tkeep.txt' ]] && echo yes || echo no)"
git -C "$repo" rm -q --cached keep.txt
run_changes "$repo"
case_result "a staged deletion is listed as staged" "$([[ "$OUT" == $'staged\tkeep.txt' ]] && echo yes || echo no)"

mkdir -p "${work}/plain/.agentic-os"
run_changes "${work}/plain"
case_result "a directory that is no repository is refused by the command" "$([[ "$RC" -ne 0 && "$OUT" == *"Not a git repository"* ]] && echo yes || echo no)"

exit "$failed"
