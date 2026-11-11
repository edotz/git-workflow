#!/usr/bin/env bash
# Git Workflow Setup
# Checks and prints the branch settings GIT_WORKFLOW_MAIN_BRANCH and GIT_WORKFLOW_RELEASE_BRANCH.
# Usage: bash bin/app git workflow-setup [validate]
# Settings: GIT_WORKFLOW_MAIN_BRANCH and GIT_WORKFLOW_RELEASE_BRANCH (default: master), read from the
#           environment; the framework loads the project-root .env at bootstrap and the environment wins
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"

cli_set_spec \
  name        "${MODULE_NAME:-workflow-setup}" \
  description "${MODULE_DESCRIPTION:-Validate the branch settings and print them.}" \
  version     "${MODULE_VERSION:-2.0.0}"

# Die when a branch setting holds whitespace; an empty setting has already fallen back to master
# Args: $1 - setting name, $2 - value
_validate_branch() {
  local key="${1:-}" value="${2:-}"
  if [[ "$value" =~ [[:space:]] ]]; then
    die_with "$BU_EXIT_CONFIG" "workflow-setup: ${key}='${value}' must be a branch name without whitespace"
  fi
  return 0
}

main() {
  cli_parse "$@"

  local option
  for option in "${!CLI_FLAGS[@]}" "${!CLI_OPTIONS[@]}"; do
    case "$option" in
      apply|check|init)
        die_with "$BU_EXIT_USAGE" "workflow-setup: --${option} is removed; branch protection and rulesets are applied with 'app git rules-sync'"
        ;;
      verbose|debug|json|dry-run|force) ;;
      *)
        die_with "$BU_EXIT_USAGE" "workflow-setup: unknown option '${option}'; usage: workflow-setup [validate]"
        ;;
    esac
  done

  local cmd
  cmd="$(cli_get_arg 0 "validate")"
  if [[ "$cmd" != "validate" ]]; then
    die_with "$BU_EXIT_USAGE" "workflow-setup: unknown command '${cmd}'; usage: workflow-setup [validate]"
  fi

  local main_branch release_branch
  main_branch="${GIT_WORKFLOW_MAIN_BRANCH:-master}"
  release_branch="${GIT_WORKFLOW_RELEASE_BRANCH:-master}"
  _validate_branch "GIT_WORKFLOW_MAIN_BRANCH" "$main_branch"
  _validate_branch "GIT_WORKFLOW_RELEASE_BRANCH" "$release_branch"

  logger_success "The branch settings are valid"
  print_line "GIT_WORKFLOW_MAIN_BRANCH    : ${main_branch}"
  print_line "GIT_WORKFLOW_RELEASE_BRANCH : ${release_branch}"
  return 0
}

main "$@"
