#!/bin/bash
# Git Branch Utility Library
# Requires: core.sh, git.sh, git
# Provides: Create the branch of a change at the head of the main branch in the checkout the developer works in

# Guard against multiple sourcing
if [[ -n "${BU_STATE_BRANCH:-}" ]]; then return 0; fi
BU_STATE_BRANCH=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BU_LIB}/git.sh"
source "${BASH_SOURCE[0]%/*}/tool.sh"

# Require git command
require_command "git" "Install git: apt-get install git"

# ============================================
# Branch Functions
# ============================================

# Refuse a branch that exists locally or on origin.
# The remote side reads the remote-tracking ref of the last fetch, as branch_create does for the main branch; the tool
# image has no credentials and no route to a local remote, and no library function fetches.
# Args:
#   $1 - branch: Branch name (e.g. "fix/my-change")
# Exits: 1 when the branch exists locally or on origin, or the refs cannot be read
# Example: branch_refuse_existing "fix/my-change"
branch_refuse_existing() {
  local branch="${1:-}" status=0
  if [[ -z "$branch" ]]; then die "branch_refuse_existing: branch required"; fi

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

# Create a branch at the head of the main branch (GIT_WORKFLOW_MAIN_BRANCH, default master) and switch the checkout to
# it, without an upstream. Uncommitted changes of the working tree go along with the switch, as git does it; git
# refuses the switch when a change would be overwritten, and warns when a detached HEAD leaves commits behind; its
# messages go to stderr, so stdout stays free for the caller.
# Args:
#   $1 - name: Branch name (e.g. "feat/add-login")
# Exits: 1 when the main branch is missing, differs from origin/<main branch>, or git refuses the switch
# Example: branch_create "feat/add-login"
branch_create() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then die "branch_create: name required"; fi

  local base_branch base_current origin_base_current
  base_branch="${GIT_WORKFLOW_MAIN_BRANCH:-master}"
  base_current="$(git rev-parse "$base_branch" 2>/dev/null)" || die "branch_create: branch '${base_branch}' not found"
  origin_base_current="$(git rev-parse "origin/${base_branch}" 2>/dev/null)" || {
    logger_warning "Cannot verify origin/${base_branch} — proceeding without remote sync check"
    origin_base_current="$base_current"
  }

  if [[ "$base_current" != "$origin_base_current" ]]; then
    die "Local ${base_branch} is not in sync with origin/${base_branch}. Run: git fetch origin && git switch ${base_branch} && git merge --ff-only origin/${base_branch}"
  fi

  git switch --no-track -c "$name" "$base_branch" >&2 || die "Failed to create the branch: ${name}"
  logger_success "Branch created: ${name}"
  return 0
}
