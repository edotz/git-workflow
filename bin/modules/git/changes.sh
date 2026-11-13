#!/usr/bin/env bash
# Git Changes - the changed files of the working tree, one per line as state, a tab and the path
# Usage: app git changes
# Output: staged, unstaged and untracked lines in that order, each state sorted by path; a file that is staged and
#         changed again is listed under both states; a rename is listed as its old path and its new path, so that a
#         commit of both paths takes the whole rename; a clean tree prints nothing
# Decisions: git lists the paths NUL separated (-z), so a path is never quoted; a path with a newline would break the line
#            format, so the command stops with an error that names the path
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${PLUGIN_LIB}/tool.sh"

cli_set_spec \
  name        "${MODULE_NAME:-changes}" \
  description "${MODULE_DESCRIPTION:-List the changed files of the working tree: staged, unstaged or untracked.}" \
  version     "${MODULE_VERSION:-1.0.0}"

_CHANGES_TMP=""

# ============================================
# Private Helpers
# ============================================

_changes_cleanup() {
  if [[ -n "$_CHANGES_TMP" ]]; then
    rm -f "$_CHANGES_TMP"
    _CHANGES_TMP=""
  fi
  return 0
}

# Print the paths a git command lists as "<state><TAB><path>", sorted. The listing goes through a file, so that a failing
# git or docker ends the command instead of leaving an empty list.
# Args: $1 - state  $2.. - the git command and its arguments, without -z
_changes_list() {
  local state="$1" path nl=$'\n'
  shift
  tool_run git -c core.quotepath=off "$@" -z </dev/null > "$_CHANGES_TMP" \
    || die "changes: git could not list the ${state} files"
  while IFS= read -r -d '' path; do
    if [[ "$path" == *"$nl"* ]]; then
      die "changes: a ${state} path holds a newline and cannot be listed one per line: ${path//"$nl"/<LF>}"
    fi
    printf '%s\t%s\n' "$state" "$path" # out:return
  done < <(sort -z "$_CHANGES_TMP")
  return 0
}

# ============================================
# Main
# ============================================

main() {
  cli_parse "$@"
  cd "$PROJECT_ROOT"
  git_ensure_repo || die_with "${BU_EXIT_FAILURE}" "Not a git repository"
  tool_image_ensure

  register_cleanup _changes_cleanup
  _CHANGES_TMP="$(mktemp)"
  _changes_list staged diff --cached --name-only --no-renames
  _changes_list unstaged diff --name-only --no-renames
  _changes_list untracked ls-files --others --exclude-standard
  return 0
}

main "$@"
