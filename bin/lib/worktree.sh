#!/bin/bash
# Git Worktree Utility Library
# Requires: core.sh, json.sh, paths.sh, git.sh, git
# Provides: Git worktree operations for isolated feature development
# Worktrees live in <GIT_WORKFLOW_WORKTREE_DIR or $HOME/worktrees>/<repo-name>/<name with / as ->.

# Guard against multiple sourcing
if [[ -n "${BU_STATE_WORKTREE:-}" ]]; then return 0; fi
BU_STATE_WORKTREE=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BU_LIB}/json.sh"
source "${BU_LIB}/paths.sh"
source "${BU_LIB}/git.sh"

# Require git command
require_command "git" "Install git: apt-get install git"

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

  git_is_repo || die_with "${BU_EXIT_FAILURE}" "worktree_get_path: not a git repository"

  # The common dir is the same inside the main worktree and inside a linked one.
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || die_with "${BU_EXIT_FAILURE}" "worktree_get_path: cannot resolve the git common dir"
  common="${common%/}"
  if [[ "${common##*/}" == ".git" ]]; then
    common="${common%/*}"
  fi
  local repo_name="${common##*/}"

  local base="${GIT_WORKFLOW_WORKTREE_DIR:-${HOME}/worktrees}"
  base="${base%/}"
  local tilde='~'
  if [[ "$base" == "$tilde" || "$base" == "$tilde/"* ]]; then
    base="${HOME}${base#"$tilde"}"
  fi
  if [[ "$base" != /* ]]; then
    die_with "${BU_EXIT_CONFIG}" "worktree_get_path: GIT_WORKFLOW_WORKTREE_DIR must be an absolute path, got '${base}'"
  fi

  # Sanitize name: replace / with - for filesystem safety
  local safe_name="${name//\//-}"
  echo "${base}/${repo_name}/${safe_name}"  # out:return
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

  local base_branch
  base_branch=$(worktree_resolve_base_branch)

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

  mkdir -p "${path%/*}"

  git worktree add "$path" -b "$name" "$base_branch" >/dev/null 2>&1 || \
    git worktree add "$path" "$name" >/dev/null 2>&1 || \
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

# Resolve the main branch name from GIT_WORKFLOW_MAIN_BRANCH (project .env or process environment).
# Returns: Branch name (stdout), defaults to "master"
# Example: worktree_resolve_base_branch
worktree_resolve_base_branch() {
  echo "${GIT_WORKFLOW_MAIN_BRANCH:-master}"  # out:return
  return 0
}

# ============================================
# Worktree Lifecycle Functions
# ============================================
