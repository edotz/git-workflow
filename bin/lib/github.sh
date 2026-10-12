#!/bin/bash
# GitHub API Utility Library
# Requires: core.sh, gh, git
# Provides: GitHub operations with error handling and validation

# Guard against multiple sourcing
if [[ -n "${BU_STATE_GITHUB:-}" ]]; then return 0; fi
BU_STATE_GITHUB=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"

# ============================================
# Repository Context
# ============================================

# Get repository full name (owner/name), respecting GH_REPO override
# Args: None
# Returns: owner/name string (stdout)
# Exits: 1 if not in a GitHub repository and GH_REPO not set
github_get_repo_fullname() {
  if [[ -n "${GH_REPO:-}" ]]; then
    logger_debug "Using repository from GH_REPO: $GH_REPO"
    echo "$GH_REPO"
    return 0
  fi

  local repo
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
  if [[ -z "$repo" ]]; then
    logger_error "Not in a GitHub repository and GH_REPO not set"
    return 1
  fi
  logger_debug "Detected repository: $repo"
  echo "$repo"
}

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
# Branch Protection Functions
# ============================================

# Get branch protection rules from GitHub
# Args: $1 - branch name
# Returns: JSON object with protection rules (stdout)
# Exits: 1 if not authenticated or not in GitHub repo
# Requires: gh CLI, git
github_get_branch_protection() {
  local branch="$1"

  # Validate authentication
  github_ensure_authenticated || return 1

  local repo
  if ! repo=$(github_get_repo_fullname); then
    return 1
  fi

  # Query branch protection rules
  # Use explicit exit code checking instead of || operator to prevent
  # gh's error output from contaminating stdout. This ensures clean JSON output
  # for downstream jq operations.
  local output
  output=$(gh api "/repos/${repo}/branches/${branch}/protection" 2>/dev/null)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    # Success: output is valid JSON protection rules
    echo "$output"
  else
    # Failure: branch not protected or API error
    logger_warning "Branch protection not configured for: $branch"
    echo '{}'
    return 0
  fi
}

# Set branch protection rules on GitHub
# Args: $1 - branch name
#       $2 - JSON protection configuration
# Returns: None (outputs success message to stderr)
# Exits: 1 on failure
# Requires: gh CLI, git
github_set_branch_protection() {
  local branch="$1"
  local config="$2"

  # Validate inputs
  if [[ -z "$branch" ]]; then
    logger_error "Branch name required"
    return 1
  fi
  if [[ -z "$config" ]]; then
    logger_error "Configuration JSON required"
    return 1
  fi

  # Validate authentication
  github_ensure_authenticated || return 1

  local repo
  if ! repo=$(github_get_repo_fullname); then
    return 1
  fi

  # Apply protection rules via GitHub API
  gh api -X PUT "/repos/${repo}/branches/${branch}/protection" \
    --input - <<< "$config" >/dev/null 2>&1 || {
    logger_error "Failed to apply branch protection"
    return 1
  }

  logger_success "Branch protection applied: $branch"
}

# ============================================
# Repository Settings Functions
# ============================================

# Get repository-level settings from GitHub
# Args: $1 - owner
#       $2 - repo name
# Returns: JSON object with repository settings (stdout)
# Exits: 1 if not authenticated or API error
# Requires: gh CLI
github_get_repo_settings() {
  local owner="${1:-}"
  local name="${2:-}"

  if [[ -z "$owner" ]]; then logger_error "Owner required"; return 1; fi
  if [[ -z "$name" ]]; then logger_error "Repo name required"; return 1; fi

  github_ensure_authenticated || return 1

  local output
  output=$(gh api "/repos/${owner}/${name}" 2>/dev/null)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo "$output"
  else
    logger_error "Failed to get repository settings: ${owner}/${name}"
    return 1
  fi
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

# Get file contents from a GitHub repository
# Args: $1 - repo (owner/name)
#       $2 - path (relative file path in repo)
#       $3 - ref (branch, tag, or commit SHA)
# Returns: JSON object with name and sha (stdout)
# Exits: 1 if not authenticated or file not found
# Requires: gh CLI
github_get_file_contents() {
  local repo="${1:-}"
  local path="${2:-}"
  local ref="${3:-}"

  if [[ -z "$repo" ]]; then logger_error "Repo required (owner/name)"; return 1; fi
  if [[ -z "$path" ]]; then logger_error "File path required"; return 1; fi
  if [[ -z "$ref" ]]; then logger_error "Ref required (branch/tag/SHA)"; return 1; fi

  github_ensure_authenticated || return 1

  local output
  output=$(gh api "repos/${repo}/contents/${path}?ref=${ref}" --jq '{name: .name, sha: .sha}' 2>/dev/null)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]] && [[ -n "$output" ]]; then
    echo "$output"
  else
    logger_debug "File not found: ${repo}/${path}@${ref}"
    return 1
  fi
}

# Apply repository-level settings via GitHub API (PATCH)
# Args: $1 - owner
#       $2 - repo name
#       $3 - JSON settings payload
# Returns: None (logs result to stderr)
# Exits: 1 on failure
# Requires: gh CLI
github_patch_repo_settings() {
  local owner="${1:-}"
  local name="${2:-}"
  local settings="${3:-}"

  if [[ -z "$owner" ]]; then logger_error "Owner required"; return 1; fi
  if [[ -z "$name" ]]; then logger_error "Repo name required"; return 1; fi
  if [[ -z "$settings" ]]; then logger_error "Settings JSON required"; return 1; fi

  github_ensure_authenticated || return 1

  gh api --method PATCH "/repos/${owner}/${name}" \
    --input - <<< "$settings" >/dev/null 2>&1 || {
    logger_error "Failed to patch repository settings: ${owner}/${name}"
    return 1
  }

  logger_success "Repository settings applied: ${owner}/${name}"
}

return 0
