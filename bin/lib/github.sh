#!/bin/bash
# GitHub API Utility Library
# Requires: core.sh, gh, git
# Provides: github_ensure_authenticated, github_get_runs

# Guard against multiple sourcing
if [[ -n "${BU_STATE_GITHUB:-}" ]]; then return 0; fi
BU_STATE_GITHUB=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"

# ============================================
# GitHub Validation Functions
# ============================================

# Ensure GitHub CLI is installed and authenticated
# Args: None
# Returns: 0 if authenticated, 1 if not
# Exits: None
# Requires: gh CLI
github_ensure_authenticated() {
  # Check if gh CLI is installed
  if ! command_exists "gh"; then
    logger_error "GitHub CLI (gh) not installed"
    logger_error "Install: https://cli.github.com/"
    return 1
  fi

  # Check if gh CLI is authenticated
  if ! gh auth status >/dev/null 2>&1; then
    logger_error "GitHub CLI not authenticated"
    logger_error "Run: gh auth login"
    return 1
  fi

  return 0
}

# ============================================
# Workflow Run Functions
# ============================================

# Get recent workflow runs for a repository
# Args: $1 - repo (owner/name, optional — defaults to current repo)
#       $2 - workflow filename (optional filter)
#       $3 - limit (optional, default 5)
# Returns: JSON array of runs (stdout)
# Exits: 1 if not authenticated or API error
# Requires: gh CLI
github_get_runs() {
  local repo="${1:-}"
  local workflow="${2:-}"
  local limit="${3:-5}"

  github_ensure_authenticated || return 1

  local args=("run" "list" "--limit" "$limit" "--json" "name,status,conclusion,url,createdAt,headBranch")
  if [[ -n "$repo" ]]; then args+=("--repo" "$repo"); fi
  if [[ -n "$workflow" ]]; then args+=("--workflow" "$workflow"); fi

  local output
  output=$(gh "${args[@]}" 2>/dev/null)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo "$output"
  else
    logger_error "Failed to fetch workflow runs${repo:+ for $repo}"
    echo "[]"
    return 1
  fi
}

return 0
