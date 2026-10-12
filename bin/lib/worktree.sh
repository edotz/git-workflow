#!/bin/bash
# Git Worktree Utility Library
# Requires: core.sh, json.sh, git
# Provides: Git worktree operations for isolated feature development

# Guard against multiple sourcing
if [[ -n "${BU_STATE_WORKTREE:-}" ]]; then return 0; fi
BU_STATE_WORKTREE=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BU_LIB}/json.sh"
source "${BU_LIB}/paths.sh"

# Require git command
require_command "git" "Install git: apt-get install git"

# ============================================
# Worktree Constants
# ============================================

readonly WORKTREE_BASE_DIR="${PROVIDER_CONFIG_DIR}/worktrees"

# ============================================
# Private Helpers
# ============================================

# Run a git command, optionally inside a specific directory.
# Args: $1 - cwd (empty = current dir), then git sub-command + args
_git_in() {
  local cwd="${1:-}"
  shift
  if [[ -n "$cwd" ]]; then
    git -C "$cwd" "$@"
  else
    git "$@"
  fi
}

# ============================================
# Worktree Functions
# ============================================

# List all worktrees in porcelain format
# Args:
#   $1 - cwd: Main repo root (optional — defaults to current directory)
# Returns: Porcelain worktree list (stdout)
# Example: worktree_list
# Example: worktree_list "/path/to/repo"
worktree_list() {
  local cwd="${1:-}"
  _git_in "$cwd" worktree list --porcelain 2>/dev/null
}

# Check if a named worktree already exists
# Args:
#   $1 - name: Worktree name (branch name)
# Returns: 0 if exists, 1 if not
# Example: worktree_exists "feature/my-feature"
worktree_exists() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "worktree_exists: name required"

  local path
  path=$(worktree_get_path "$name")
  [[ -d "$path" ]]
}

# Get the filesystem path for a named worktree
# Args:
#   $1 - name: Worktree name (branch name)
# Returns: Absolute path to worktree directory (stdout)
# Example: worktree_get_path "feature/my-feature"
worktree_get_path() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "worktree_get_path: name required"

  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || die "worktree_get_path: not a git repository"

  # Sanitize name: replace / with - for filesystem safety
  local safe_name="${name//\//-}"
  echo "${root}/${WORKTREE_BASE_DIR}/${safe_name}"
}

# Create a new worktree for a branch
# Args:
#   $1 - name: Branch name (e.g. "feature/my-feature")
# Returns: Absolute path to created worktree (stdout)
# Exits: 1 if worktree already exists or base branch not up-to-date
# Example: worktree_create "feature/my-feature"
worktree_create() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "worktree_create: name required"

  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || die "worktree_create: not a git repository"

  local base_branch
  base_branch=$(worktree_resolve_base_branch "$root")

  local path
  path=$(worktree_get_path "$name")

  worktree_prune

  if worktree_exists "$name"; then
    die "Worktree already exists: $path"
  fi

  local base_current
  base_current=$(git rev-parse "$base_branch" 2>/dev/null) || die "worktree_create: branch '$base_branch' not found"
  local origin_base_current
  origin_base_current=$(git rev-parse "origin/$base_branch" 2>/dev/null) || {
    logger_warning "Cannot verify origin/$base_branch — proceeding without remote sync check"
    origin_base_current="$base_current"
  }

  if [[ "$base_current" != "$origin_base_current" ]]; then
    die "Local $base_branch is not in sync with origin/$base_branch. Run: git fetch origin && git merge origin/$base_branch"
  fi

  logger_info "Creating worktree: $name"
  logger_debug "Path: $path"

  mkdir -p "$(dirname "$path")"

  git worktree add "$path" -b "$name" "$base_branch" 2>/dev/null || \
    git worktree add "$path" "$name" 2>/dev/null || \
    die "Failed to create worktree for branch: $name"

  logger_success "Worktree created: $path"
  echo "$path"
}

# Prune stale worktree references
# Args:
#   $1 - cwd: Main repo root (optional — defaults to current directory)
# Returns: None
# Example: worktree_prune
# Example: worktree_prune "/path/to/repo"
worktree_prune() {
  local cwd="${1:-}"
  logger_info "Pruning stale worktrees"
  _git_in "$cwd" worktree prune 2>/dev/null || { logger_warning "Worktree prune failed"; return 1; }
  logger_success "Worktree prune complete"
}

# Resolve the main branch name from .github/workflow.env.
# Args:
#   $1 - cwd: Main repo root (absolute path)
# Returns: Branch name (stdout), defaults to "master"
# Example: worktree_resolve_base_branch "$cwd"
worktree_resolve_base_branch() {
  local cwd="${1:-}"
  [[ -n "$cwd" ]] || die "worktree_resolve_base_branch: cwd required"

  local base_branch="master"
  local workflow_env="${cwd}/.github/workflow.env"

  if [[ -f "$workflow_env" ]]; then
    local mb
    mb="$(grep -E '^MAIN_BRANCH=' "$workflow_env" | cut -d= -f2 | tr -d '"' | tr -d "'")"
    [[ -n "$mb" ]] && base_branch="$mb"
  fi

  echo "$base_branch"
}

# ============================================
# Worktree Lifecycle Functions
# ============================================
