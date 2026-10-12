#!/usr/bin/env bash
# Git Workflow Status Data Collector
# Collects structured data for Human-Responsibility Trunk-Based Development workflow
# Output: JSON for Claude synthesis

set -euo pipefail

# ============================================
# Load Libraries
# ============================================
source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/git.sh"
source "${BU_LIB}/json.sh"
source "${PLUGIN_ROOT}/bin/lib/github.sh"
source "${BU_LIB}/cli.sh"

# Load workflow.env with override — project config takes precedence over ambient shell
WORKFLOW_ENV_FILE="${PROJECT_ROOT}/.github/workflow.env"
[[ -f "$WORKFLOW_ENV_FILE" ]] && env_parse_file "$WORKFLOW_ENV_FILE" "true" "workflow.env" || true

# ============================================
# Configuration
# ============================================
readonly MAIN_BRANCH="${PLUGIN_EDOTZ_GIT_WORKFLOW_MAIN_BRANCH}"
readonly RELEASE_BRANCH="${PLUGIN_EDOTZ_GIT_WORKFLOW_RELEASE_BRANCH}"
readonly PACKAGE_FILE="${PACKAGE_FILE:-package.json}"

# ============================================
# Business Logic Functions
# ============================================

# Get current version from package.json
# Args: $1 - package file path (optional, defaults to package.json)
# Returns: Version string or "unknown"
get_current_version() {
  local package_file="${1:-$PACKAGE_FILE}"
  json_get_file_with_default "$package_file" "version" "unknown"
}

# Get sync status between branches
# Args: $1 - main branch, $2 - release branch
# Returns: JSON object with ahead/behind counts
get_sync_status() {
  local main_branch="$1"
  local release_branch="$2"
  
  local ahead
  local behind
  
  ahead=$(git rev-list --count "$release_branch..$main_branch" 2>/dev/null || echo "0")
  behind=$(git rev-list --count "$main_branch..$release_branch" 2>/dev/null || echo "0")
  
  jq -n \
    --argjson ahead "$ahead" \
    --argjson behind "$behind" \
    '{"ahead": $ahead, "behind": $behind}'
}

# Get working tree status
# Args: None
# Returns: JSON object with clean status and file counts
get_working_tree_status() {
  # Delegates to git_get_workdir_status() from lib/git.sh (DRY principle)
  # Avoids duplicating 20 lines of code that already exists in library
  git_get_workdir_status
}

# Count conventional commits by type (uses git_conventional_commit_stats from lib/git.sh)
# This function now uses library function to avoid duplication
count_conventional_commits() {
  local range="$1"

  # Use library function which returns full stats JSON
  git_conventional_commit_stats "$range"
}

# Count breaking changes (DRY - extracted from commit stats)
# Breaking changes are included in git_conventional_commit_stats output
count_breaking_changes() {
  local range="$1"

  # Use library function and extract breaking count using json.sh
  local stats
  stats=$(git_conventional_commit_stats "$range")
  json_get_with_default "$stats" "breaking" "0"
}

# Get detailed commit list (DRY - uses git_get_commit_details from lib/git.sh)
# Uses library function to avoid duplicating git log JSON formatting
get_commit_details() {
  local range="$1"
  local max_count="${2:-50}"

  git_get_commit_details "$range" "$max_count"
}

# Get PR status from GitHub
# Args: $1 - release branch
# Returns: JSON object with release and backport PRs
get_pr_status() {
  local release_branch="$1"
  
  local release_prs='[]'
  local backport_prs='[]'
  
  if command_exists "gh"; then
    # Check for release PRs - use json.sh for filtering
    all_release_prs=$(gh pr list --base "$release_branch" \
      --json number,title,state,headRefName,updatedAt 2>/dev/null || echo '[]')
    release_prs=$(json_array_filter "$all_release_prs" '.headRefName | startswith("release-please--")' || echo '[]')

    # Check for backport PRs - use json.sh for filtering
    all_backport_prs=$(gh pr list --base "$MAIN_BRANCH" \
      --json number,title,state,headRefName,updatedAt 2>/dev/null || echo '[]')
    backport_prs=$(json_array_filter "$all_backport_prs" '.headRefName | startswith("backport/")' || echo '[]')
  fi
  
  jq -n \
    --argjson release "$release_prs" \
    --argjson backport "$backport_prs" \
    '{"release": $release, "backport": $backport}'
}

# Get branch protection status
# Args: None
# Returns: JSON object; compliance is not verified, so compliant and drift are always null
get_branch_protection_status() {
  if [[ ! -f "${PROJECT_ROOT}/.github/branch-protection.yaml" ]]; then
    echo '{"configured":false,"compliant":null,"drift":null}'  # out:return
    return 0
  fi
  echo '{"configured":true,"compliant":null,"drift":null}'  # out:return
}

# Get release pipeline status from GitHub Actions
# Args: None
# Returns: JSON object with most recent run status, or null fields if unavailable
get_pipeline_status() {
  if ! github_ensure_authenticated 2>/dev/null; then
    echo '{"available":false,"status":null,"conclusion":null,"name":null,"branch":null,"url":null}'  # out:return
    return 0
  fi

  local runs
  runs=$(github_get_runs "" "" "1" 2>/dev/null || echo "[]")

  local run_count
  run_count=$(json_length "$runs")

  if [[ "$run_count" == "0" ]] || [[ -z "$run_count" ]]; then
    echo '{"available":true,"status":null,"conclusion":null,"name":null,"branch":null,"url":null}'  # out:return
    return 0
  fi

  jq '.[0] | {available: true, status: .status, conclusion: .conclusion, name: .name, branch: .headBranch, url: .url}' <<< "$runs"
}

# Assemble complete workflow status
# Args: None
# Returns: JSON object with complete status
get_workflow_status() {
  # Get basic info
  local current_branch
  current_branch=$(git_get_current_branch)
  
  local current_version
  current_version=$(get_current_version)
  
  # Get sync status
  local sync_status
  sync_status=$(get_sync_status "$MAIN_BRANCH" "$RELEASE_BRANCH")
  
  local ahead
  local behind
  ahead=$(json_get "$sync_status" "ahead")
  behind=$(json_get "$sync_status" "behind")
  
  # Get working tree status
  local working_tree
  working_tree=$(get_working_tree_status)
  
  # Count unreleased commits
  local feat_count=0
  local fix_count=0
  local breaking_count=0
  local commits_json='[]'
  
  if [[ "$ahead" -gt 0 ]]; then
    feat_count=$(count_conventional_commits "$RELEASE_BRANCH..$MAIN_BRANCH" "feat")
    fix_count=$(count_conventional_commits "$RELEASE_BRANCH..$MAIN_BRANCH" "fix")
    breaking_count=$(count_breaking_changes "$RELEASE_BRANCH..$MAIN_BRANCH")
    commits_json=$(get_commit_details "$RELEASE_BRANCH..$MAIN_BRANCH" 50)
  fi
  
  # Get PR status
  local pr_status
  pr_status=$(get_pr_status "$RELEASE_BRANCH")
  
  # Get branch protection
  local protection_status
  protection_status=$(get_branch_protection_status)

  # Get release pipeline status
  local pipeline_status
  pipeline_status=$(get_pipeline_status)

  # Assemble final JSON
  jq -n \
    --arg branch "$current_branch" \
    --arg version "$current_version" \
    --argjson ahead "$ahead" \
    --argjson behind "$behind" \
    --argjson feat "$feat_count" \
    --argjson fix "$fix_count" \
    --argjson breaking "$breaking_count" \
    --argjson commits "$commits_json" \
    --argjson working_tree "$working_tree" \
    --argjson prs "$pr_status" \
    --argjson protection "$protection_status" \
    --argjson pipeline "$pipeline_status" \
    '{
      current_branch: $branch,
      current_version: $version,
      sync_status: {
        ahead_of_release: $ahead,
        behind_release: $behind
      },
      working_tree: $working_tree,
      unreleased_commits: {
        feat: $feat,
        fix: $fix,
        breaking: $breaking,
        details: $commits
      },
      pending_prs: $prs,
      branch_protection: $protection,
      pipeline: $pipeline
    }'
}

# ============================================
# Main Function
# ============================================
cli_set_spec \
  name        "${MODULE_NAME:-workflow-status}" \
  description "${MODULE_DESCRIPTION:-}" \
  version     "${MODULE_VERSION:-1.0.0}"

main() {
  cli_parse "$@"

  # Ensure we're in a git repository
  git_ensure_repo || die "Not a git repository"
  
  # Fetch latest from remote (silent) — ensures remote branches are available locally
  git fetch origin "$MAIN_BRANCH" "$RELEASE_BRANCH" 2>/dev/null || true

  # Check if release branch exists (local or remote)
  if ! git rev-parse --verify "$RELEASE_BRANCH" > /dev/null 2>&1 && \
     ! git rev-parse --verify "origin/$RELEASE_BRANCH" > /dev/null 2>&1; then
    die "Release branch '$RELEASE_BRANCH' does not exist"
  fi
  
  # Get and output workflow status
  get_workflow_status
}

main "$@"
