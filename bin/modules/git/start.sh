#!/usr/bin/env bash
# Git Start - the branch <type>/<name> from the main branch, checked out in the current checkout
# Usage: app git start <type> <name>
# Settings: GIT_WORKFLOW_MAIN_BRANCH (default: master)
# Output: the name of the new branch on stdout
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${BU_LIB}/output.sh"
source "${PLUGIN_LIB}/tool.sh"
source "${PLUGIN_LIB}/branch.sh"

cli_set_spec \
  name        "${MODULE_NAME:-start}" \
  description "${MODULE_DESCRIPTION:-Create the branch <type>/<name> from the main branch, switch to it and print its name.}" \
  version     "${MODULE_VERSION:-1.0.0}"

# The types of commitlint.config.mjs (type-enum)
readonly START_TYPES=(feat fix docs style refactor perf test build ci chore)
readonly START_NAME_RE='^[a-z0-9]+(-[a-z0-9]+)*$'

# ============================================
# Private Helpers
# ============================================

# Refuse a branch that exists locally or on origin.
# The remote side reads the remote-tracking ref of the last fetch, as branch_create does for the main branch; the tool
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

  branch_create "$branch"
  print_line "$branch"
  return 0
}

main "$@"
