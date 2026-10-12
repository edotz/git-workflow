#!/usr/bin/env bash
# Git Worktree Module
# Manages git worktrees for isolated feature development
# Uses lib/worktree.sh for worktree operations

set -euo pipefail

# ============================================
# Load Libraries
# ============================================
source "${BU_ROOT}/lib/core.sh"
source "${PLUGIN_ROOT}/bin/lib/worktree.sh"
source "${BU_LIB}/git.sh"
source "${BU_LIB}/cli.sh"

# ============================================
# CLI Specification
# ============================================
cli_set_spec \
  name        "${MODULE_NAME:-worktree}" \
  description "${MODULE_DESCRIPTION:-}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_option "start" "s" "Create a worktree for a new branch and print its path" ""
cli_add_flag "list" "l" "List all active worktrees"
cli_add_flag "prune" "p" "Prune stale worktree references"

# ============================================
# Business Logic
# ============================================

# Format and print worktree list
# Args: None
# Returns: Formatted worktree list
print_worktree_list() {
  local raw
  raw=$(worktree_list)

  if [[ -z "$raw" ]]; then
    logger_info "No active worktrees"
    return 0
  fi

  logger_info "Active worktrees:"
  local worktree="" branch="" bare=""
  while IFS= read -r line; do
    if [[ "$line" == worktree* ]]; then
      worktree="${line#worktree }"
    elif [[ "$line" == branch* ]]; then
      branch="${line#branch refs/heads/}"
    elif [[ "$line" == "bare" ]]; then
      bare="true"
    elif [[ -z "$line" ]]; then
      if [[ -n "$worktree" ]] && [[ "${bare:-}" != "true" ]]; then
        logger_info "  ${branch:-HEAD} → $worktree"
      fi
      worktree="" branch="" bare=""
    fi
  done <<< "$raw"
}

# ============================================
# Main Function
# ============================================
main() {
  cli_parse "$@"

  git_ensure_repo || die "Not a git repository"

  local start_name
  start_name=$(cli_get_option "start" "")

  if [[ -n "$start_name" ]]; then
    local path
    path=$(worktree_create "$start_name") || exit 1
    echo "$path"  # out:return
    return 0
  fi

  if cli_flag_is_set "list"; then
    print_worktree_list
    return 0
  fi

  if cli_flag_is_set "prune"; then
    worktree_prune
    return 0
  fi

  # Default: list
  print_worktree_list
}

main "$@"
