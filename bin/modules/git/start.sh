#!/usr/bin/env bash
# Git Start - a branch <type>/<name> and its worktree from the main branch
# Usage: app git start <type> <name>
# Settings: GIT_WORKFLOW_MAIN_BRANCH (default: master), GIT_WORKFLOW_WORKTREE_DIR (absolute, default: $HOME/worktrees)
# Output: the absolute path of the new worktree on stdout
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${BU_LIB}/output.sh"
source "${PLUGIN_LIB}/tool.sh"
source "${PLUGIN_LIB}/worktree.sh"

cli_set_spec \
  name        "${MODULE_NAME:-start}" \
  description "${MODULE_DESCRIPTION:-Create the branch <type>/<name> and its worktree from the main branch and print the worktree path.}" \
  version     "${MODULE_VERSION:-1.0.0}"

# The types of commitlint.config.mjs (type-enum)
readonly START_TYPES=(feat fix docs style refactor perf test build ci chore)
readonly START_NAME_RE='^[a-z0-9]+(-[a-z0-9]+)*$'

# ============================================
# Private Helpers
# ============================================

# Refuse a branch that exists locally or on origin: worktree_create would check an existing branch out instead of failing.
# The remote side reads the remote-tracking ref of the last fetch, as worktree_create does for the main branch; the tool
# image has no credentials and no route to a local remote, and no library function fetches.
# Args: $1 - branch
_start_refuse_existing() {
  local branch="$1" status=0

  tool_run git rev-parse --verify --quiet "refs/heads/${branch}" </dev/null >/dev/null || status=$?
  if [[ "$status" -eq 0 ]]; then
    die_with "${BU_EXIT_FAILURE}" "Branch exists locally: ${branch}"
  elif [[ "$status" -ne 1 ]]; then
    die_with "${BU_EXIT_FAILURE}" "Cannot read the refs of the repository (status ${status})"
  fi

  status=0
  tool_run git rev-parse --verify --quiet "refs/remotes/origin/${branch}" </dev/null >/dev/null || status=$?
  if [[ "$status" -eq 0 ]]; then
    die_with "${BU_EXIT_FAILURE}" "Branch exists on origin: ${branch}"
  elif [[ "$status" -ne 1 ]]; then
    die_with "${BU_EXIT_FAILURE}" "Cannot read the refs of the repository (status ${status})"
  fi
  return 0
}

# ============================================
# Main Function
# ============================================
main() {
  cli_parse "$@"

  git_ensure_repo || die_with "${BU_EXIT_FAILURE}" "Not a git repository"

  local type name
  type="$(cli_get_arg 0 "")"
  name="$(cli_get_arg 1 "")"

  if [[ -z "$type" || -z "$name" ]]; then
    die_with "${BU_EXIT_USAGE}" "Usage: app git start <type> <name>"
  fi

  local known=0 t
  for t in "${START_TYPES[@]}"; do
    if [[ "$t" == "$type" ]]; then known=1; fi
  done
  if [[ "$known" -eq 0 ]]; then
    die_with "${BU_EXIT_USAGE}" "Unknown type '${type}': one of ${START_TYPES[*]}"
  fi

  if [[ ! "$name" =~ $START_NAME_RE ]]; then
    die_with "${BU_EXIT_USAGE}" "Invalid name '${name}': lower case letters and digits, separated by single hyphens"
  fi

  local branch="${type}/${name}"
  _start_refuse_existing "$branch"

  local path
  path="$(worktree_create "$branch")" || exit "$?"
  print_line "$path"
  return 0
}

main "$@"
