#!/usr/bin/env bash
# Test of app git commit on a throwaway repository, with a stub provider command.
# Usage: bash tests/git-commit/run.sh
# Needs: git, docker (the commit runs in the tool image), node_modules of the plugin (commitlint)
set -euo pipefail

TEST_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PLUGIN_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
BU_ROOT="${BU_ROOT:-/home/ohoeft/workspace/edotz.claude-code/bin}"
export PLUGIN_ROOT BU_ROOT
export PLUGIN_LIB="${PLUGIN_ROOT}/bin/lib"

COMMIT="${PLUGIN_ROOT}/bin/modules/git/commit.sh"
WORK="$(mktemp -d)"
REPO="${WORK}/repo"
STUB="${WORK}/stub-provider"
STUB_LOG="${WORK}/stub.log"
OUT="${WORK}/out.txt"
FAILURES=0
trap 'rm -rf "$WORK"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

check() {
  local label="$1"
  shift
  if "$@"; then
    printf 'ok:   %s\n' "$label"
  else
    fail "$label"
  fi
}

# The stub provider command: it logs its arguments and prints STUB_REPLY.
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${STUB_LOG}"
printf '%s\n' "${STUB_REPLY}"
exit "${STUB_EXIT:-0}"
EOF
chmod +x "$STUB"
export STUB_LOG CLAUDE_BIN="$STUB"
unset ANTHROPIC_API_KEY

mkdir -p "$REPO/.agentic-os"
cd "$REPO"
git init -q -b master .
git config user.name "Test Developer"
git config user.email "dev@example.test"
printf 'one\n' > base.txt
git add base.txt
git -c core.hooksPath=/dev/null commit -q -m "chore: add the base file"
printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Run the command with the given stdin text; the output goes to $OUT, the status to RC.
run() {
  local input="$1"
  shift
  RC=0
  printf '%s' "$input" | bash "$COMMIT" "$@" > "$OUT" 2>&1 || RC=$?
}

head_count() { git rev-list --count HEAD; }
index_tree() { git write-tree; }

# 1. --message with --yes: one commit, the message, the identity, no hook, only the named paths, no provider call.
printf 'two\n' > a.txt
printf 'three\n' > other.txt
git add other.txt
before="$(head_count)"
run "" --message "feat(core): add the a file" --yes a.txt
check "message and --yes: exit 0" test "$RC" -eq 0
check "message and --yes: one new commit" test "$(head_count)" -eq $((before + 1))
check "message and --yes: the subject" test "$(git log -1 --format=%s)" = "feat(core): add the a file"
check "message and --yes: the identity" test "$(git log -1 --format='%an <%ae>')" = "Test Developer <dev@example.test>"
check "message and --yes: only the named path" test "$(git show --name-only --format= HEAD)" = "a.txt"
check "message and --yes: the other staged file stays staged" test "$(git diff --cached --name-only)" = "other.txt"
check "message and --yes: the provider was not called" test ! -e "$STUB_LOG"
git reset -q other.txt
rm -f other.txt

# 2. --yes before the paths: the first path is not taken for the value of --yes.
printf 'four\n' > b.txt
before="$(head_count)"
run "" --message "chore: add the b file" --yes b.txt
check "--yes before the path: committed" test "$(git show --name-only --format= HEAD)" = "b.txt"
check "--yes before the path: one new commit" test "$(head_count)" -eq $((before + 1))

# 3. Drafted message, confirmed: the provider got the staged diff, the reply is the message.
printf 'five\n' > c.txt
export STUB_REPLY="feat(core): add the c file"
before="$(head_count)"
run "y" c.txt
check "drafted and confirmed: exit 0" test "$RC" -eq 0
check "drafted and confirmed: the reply is the subject" test "$(git log -1 --format=%s)" = "feat(core): add the c file"
check "drafted and confirmed: the message was shown" grep -q "feat(core): add the c file" "$OUT"
check "drafted and confirmed: the diff reached the provider" grep -q "+++ b/c.txt" "$STUB_LOG"

# 4. Drafted message, declined: nothing committed, the index as it was.
printf 'six\n' > d.txt
tree="$(index_tree)"
before="$(head_count)"
run "n" d.txt
check "declined: non-zero exit" test "$RC" -ne 0
check "declined: no commit" test "$(head_count)" -eq "$before"
check "declined: the index as it was" test "$(index_tree)" = "$tree"
check "declined: the file is untracked again" test "$(git ls-files d.txt)" = ""

# 5. End of input declines.
run "" d.txt
check "end of input: non-zero exit" test "$RC" -ne 0
check "end of input: no commit" test "$(head_count)" -eq "$before"

# 6. A refused lint: nothing committed, the index as it was, even with --yes.
run "" --message "added stuff" --yes d.txt
check "lint refused: exit 3" test "$RC" -eq 3
check "lint refused: no commit" test "$(head_count)" -eq "$before"
check "lint refused: the index as it was" test "$(index_tree)" = "$tree"

# 7. --yes does not skip the confirmation of a drafted message.
run "" --yes d.txt
check "--yes without --message: still asks" test "$RC" -ne 0
check "--yes without --message: no commit" test "$(head_count)" -eq "$before"

# 8. No provider and no --message: it says so, asks for --message, stages nothing. The claude binary is taken out of
# CLAUDE_BIN, the PATH and the home directory of the adapter's candidates.
no_provider_path=""
IFS=: read -ra path_dirs <<< "$PATH"
for dir in "${path_dirs[@]}"; do
  if [[ ! -x "${dir}/claude" ]]; then
    no_provider_path+="${no_provider_path:+:}${dir}"
  fi
done
mkdir -p "${WORK}/home"
(
  unset CLAUDE_BIN
  export DOCKER_CONFIG="${DOCKER_CONFIG:-${HOME}/.docker}" HOME="${WORK}/home" PATH="$no_provider_path"
  run "y" d.txt
  printf '%s\n' "$RC" > "${WORK}/rc"
)
check "no provider: non-zero exit" test "$(< "${WORK}/rc")" -ne 0
check "no provider: says so and asks for --message" grep -q "no provider is available.*--message" "$OUT"
check "no provider: no commit" test "$(head_count)" -eq "$before"
check "no provider: the index as it was" test "$(index_tree)" = "$tree"

# 9. No paths and nothing staged: it says so and commits nothing.
run "" --message "chore: nothing" --yes
check "no paths, nothing staged: non-zero exit" test "$RC" -ne 0
check "no paths, nothing staged: says nothing is staged" grep -q "nothing staged" "$OUT"
check "no paths, nothing staged: no commit" test "$(head_count)" -eq "$before"

# 9b. No paths: exactly the staged files are committed; an unstaged change and an untracked file stay as they are.
printf 'g\n' > g.txt
printf 'h\n' > h.txt
printf 'changed\n' >> base.txt
git add g.txt h.txt
before="$(head_count)"
run "" --message "feat(core): add the g and h files" --yes
check "no paths, staged: exit 0" test "$RC" -eq 0
check "no paths, staged: one new commit" test "$(head_count)" -eq $((before + 1))
check "no paths, staged: exactly the staged files" test "$(git show --name-only --format= HEAD | sort | tr '\n' ' ')" = "g.txt h.txt "
check "no paths, staged: the unstaged change stays unstaged" test "$(git diff --name-only)" = "base.txt"
check "no paths, staged: the untracked file stays untracked" test "$(git ls-files --others --exclude-standard | tr '\n' ' ')" = "d.txt "
git checkout -q -- base.txt

# 9c. No paths, drafted message, confirmed: the staged diff reached the provider.
printf 'i\n' > i.txt
git add i.txt
export STUB_REPLY="feat(core): add the i file"
before="$(head_count)"
run "y"
check "no paths, drafted: exit 0" test "$RC" -eq 0
check "no paths, drafted: the reply is the subject" test "$(git log -1 --format=%s)" = "feat(core): add the i file"
check "no paths, drafted: the staged diff reached the provider" grep -q "+++ b/i.txt" "$STUB_LOG"

# 9c2. No paths, a rename in the index: the old path goes with the new one.
git mv base.txt renamed.txt
before="$(head_count)"
run "" --message "chore: rename the base file" --yes
check "no paths, rename: exit 0" test "$RC" -eq 0
check "no paths, rename: one new commit" test "$(head_count)" -eq $((before + 1))
check "no paths, rename: nothing stays staged" test -z "$(git diff --cached --name-only)"
git mv renamed.txt base.txt
git -c core.hooksPath=/dev/null commit -q -m "chore: restore the base file"

# 9d. No paths, declined: the staged file stays staged and nothing is committed.
printf 'j\n' > j.txt
git add j.txt
tree="$(index_tree)"
before="$(head_count)"
run "n"
check "no paths, declined: non-zero exit" test "$RC" -ne 0
check "no paths, declined: no commit" test "$(head_count)" -eq "$before"
check "no paths, declined: the file stays staged" test "$(index_tree)" = "$tree"
git reset -q j.txt
rm -f j.txt

# 10. Nothing to commit in the paths named.
run "" --message "chore: nothing" --yes base.txt
check "nothing to commit: non-zero exit" test "$RC" -ne 0
check "nothing to commit: no commit" test "$(head_count)" -eq "$before"

# 11. A reply wrapped in a code fence: the fence is dropped and the message is committed.
printf 'seven\n' > e.txt
export STUB_REPLY=$'```\nfeat(core): add the e file\n```'
before="$(head_count)"
run "y" e.txt
check "fenced reply: exit 0" test "$RC" -eq 0
check "fenced reply: the subject without the fence" test "$(git log -1 --format=%s)" = "feat(core): add the e file"
check "fenced reply: one new commit" test "$(head_count)" -eq $((before + 1))

# 12. A provider that fails: nothing committed, the index as it was.
printf 'eight\n' > f.txt
export STUB_REPLY="feat(core): add the f file" STUB_EXIT=1
tree="$(index_tree)"
before="$(head_count)"
run "y" f.txt
unset STUB_EXIT
check "failing provider: non-zero exit" test "$RC" -ne 0
check "failing provider: no commit" test "$(head_count)" -eq "$before"
check "failing provider: the index as it was" test "$(index_tree)" = "$tree"

if [[ "$FAILURES" -ne 0 ]]; then
  printf '%s check(s) failed\n' "$FAILURES"
  exit 1
fi
printf 'all checks passed\n'
