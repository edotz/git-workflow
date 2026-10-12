#!/usr/bin/env bash
# Git Branch Cleanup Module
# Identifies merged, stale, and safe-to-delete branches
# Output: Interactive cleanup with safety checks

set -euo pipefail

# ============================================
# Load Libraries
# ============================================
source "${BU_ROOT}/lib/core.sh"
# Source additional libraries (now BU_LIB is available)
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${BU_LIB}/json.sh"

# ============================================
# Configuration
# ============================================
readonly MAIN_BRANCH="${PLUGIN_EDOTZ_GIT_WORKFLOW_MAIN_BRANCH}"
readonly RELEASE_BRANCH="${PLUGIN_EDOTZ_GIT_WORKFLOW_RELEASE_BRANCH}"
readonly STALE_DAYS="${PLUGIN_EDOTZ_GIT_WORKFLOW_STALE_DAYS}"

# ============================================
# CLI Specification
# ============================================
cli_set_spec \
  name        "${MODULE_NAME:-branch-cleanup}" \
  description "${MODULE_DESCRIPTION:-}" \
  version     "${MODULE_VERSION:-2.0.0}"

cli_add_flag "dry-run" "d" "Preview changes without deleting"
cli_add_flag "force" "f" "Skip confirmation prompt"
cli_add_flag "remote-only" "r" "Only analyze remote branches"
cli_add_flag "local-only" "l" "Only analyze local branches"

# ============================================
# Business Logic Functions
# ============================================

# Check if branch is protected
# Args: $1 - branch name
# Returns: 0 if protected, 1 otherwise
is_protected() {
  local branch="$1"
  local protected_branches=("$MAIN_BRANCH" "$RELEASE_BRANCH" "main" "master" "develop" "development" "staging" "production")
  
  for pb in "${protected_branches[@]}"; do
    if [[ "$branch" == "$pb" ]]; then
      return 0
    fi
  done
  
  # Special patterns
  if [[ "$branch" == "release-please--"* ]] || [[ "$branch" == "backport/"* ]]; then
    return 0
  fi
  
  return 1
}

# Calculate branch age in days
# Args: $1 - git ref (branch or origin/branch)
# Returns: Age in days
calculate_days_old() {
  local ref="$1"
  local timestamp
  
  timestamp=$(git log -1 --format=%ct "$ref" 2>/dev/null || echo "0")
  if [[ "$timestamp" == "0" ]]; then
    echo "0"  # out:return
    return 0
  fi
  
  local current_timestamp
  current_timestamp=$(date +%s)
  echo $(( (current_timestamp - timestamp) / 86400 ))  # out:return
}

# Dispatch branch analysis to local or remote analyzer
# Args: $1 - scope: "local" | "remote"
# Returns: JSON with categorized branches
analyze_branches() {
  local scope="${1:-}"
  if [[ "$scope" == "remote" ]]; then
    analyze_remote_branches
  else
    analyze_local_branches
  fi
}

# Analyze local branches
# Args: None
# Returns: JSON with categorized branches
analyze_local_branches() {
  local merged_local=()
  local stale_local=()
  local active_local=()
  
  git fetch --prune origin 2>/dev/null || true
  
  while IFS= read -r branch; do
    # Skip protected branches
    # shellcheck disable=SC2310
    if is_protected "$branch"; then
      continue
    fi
    
    # Check if merged
    if git branch --merged "$MAIN_BRANCH" 2>/dev/null | grep -q "^[* ]*${branch}$"; then
      merged_local+=("$branch")
    else
      # Check age
      local days_old
      days_old=$(calculate_days_old "$branch")
      
      if [[ "$days_old" -gt "$STALE_DAYS" ]]; then
        stale_local+=("$branch:$days_old")
      else
        active_local+=("$branch:$days_old")
      fi
    fi
  done < <(git branch --format='%(refname:short)' 2>/dev/null | grep -v "^${MAIN_BRANCH}$\|^${RELEASE_BRANCH}$")
  
  # Output as JSON (using library function to avoid duplication)
  jq -n \
    --argjson merged "$(json_array_from_bash "${merged_local[@]}")" \
    --argjson stale "$(json_array_from_bash "${stale_local[@]}")" \
    --argjson active "$(json_array_from_bash "${active_local[@]}")" \
    '{merged: $merged, stale: $stale, active: $active}'
}

# Analyze remote branches
# Args: None
# Returns: JSON with categorized branches
analyze_remote_branches() {
  local merged_remote=()
  local stale_remote=()
  local active_remote=()
  
  while IFS= read -r branch; do
    # Remove origin/ prefix
    branch="${branch#origin/}"

    # Skip protected branches
    # shellcheck disable=SC2310
    if is_protected "$branch"; then
      continue
    fi
    
    # Check if merged
    if git branch -r --merged "origin/$MAIN_BRANCH" 2>/dev/null | grep -q "origin/${branch}$"; then
      merged_remote+=("$branch")
    else
      # Check age
      local days_old
      days_old=$(calculate_days_old "origin/$branch")
      
      if [[ "$days_old" -gt "$STALE_DAYS" ]]; then
        stale_remote+=("$branch:$days_old")
      else
        active_remote+=("$branch:$days_old")
      fi
    fi
  done < <(git branch -r --format='%(refname:short)' 2>/dev/null | grep -v "HEAD\|^origin/${MAIN_BRANCH}$\|^origin/${RELEASE_BRANCH}$")
  
  # Output as JSON (using library function to avoid duplication)
  jq -n \
    --argjson merged "$(json_array_from_bash "${merged_remote[@]}")" \
    --argjson stale "$(json_array_from_bash "${stale_remote[@]}")" \
    --argjson active "$(json_array_from_bash "${active_remote[@]}")" \
    '{merged: $merged, stale: $stale, active: $active}'
}

# Format and display analysis report
# Args: $1 - local analysis JSON, $2 - remote analysis JSON
display_report() {
  local local_json="$1"
  local remote_json="$2"
  local local_only="${3:-false}"
  local remote_only="${4:-false}"
  
  logger_info "🧹 Branch Cleanup Report"
  print_line "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_line ""
  
  # Display analysis (simplified - actual implementation formats JSON)
  print_line "Use --dry-run to preview, --force to skip confirmation"
  print_line ""
}

# ============================================
# Main Function
# ============================================
main() {
  cli_parse "$@"
  
  # Validate git repository
  git_ensure_repo || die "Not a git repository"
  
  # Get options
  local dry_run=false
  local force=false
  local remote_only=false
  local local_only=false
  
  if cli_flag_is_set "dry-run"; then dry_run=true; fi
  if cli_flag_is_set "force"; then force=true; fi
  if cli_flag_is_set "remote-only"; then remote_only=true; fi
  if cli_flag_is_set "local-only"; then local_only=true; fi
  
  logger_info "🔄 Fetching latest from remote..."
  
  # Analyze branches
  local local_analysis
  local remote_analysis
  
  if [[ "$remote_only" == "false" ]]; then
    logger_info "Analyzing local branches..."
    local_analysis=$(analyze_branches "local")
  else
    local_analysis='{"merged":[],"stale":[],"active":[]}'
  fi
  
  if [[ "$local_only" == "false" ]]; then
    logger_info "Analyzing remote branches..."
    remote_analysis=$(analyze_branches "remote")
  else
    remote_analysis='{"merged":[],"stale":[],"active":[]}'
  fi
  
  # Display report
  display_report "$local_analysis" "$remote_analysis" "$local_only" "$remote_only"
  
  # Dry-run mode
  if [[ "$dry_run" == "true" ]]; then
    logger_info "Dry-run mode: No branches will be deleted"
    exit 0
  fi
  
  # Get counts
  local merged_count
  merged_count=$(jq -s 'map(.merged | length) | add' <<< "$local_analysis $remote_analysis" || echo "0")
  
  if [[ "$merged_count" -eq 0 ]]; then
    logger_success "Repository is clean - no action needed"
    exit 0
  fi
  
  # Confirmation (unless --force)
  if [[ "$force" == "false" ]]; then
    print_line "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -p "Delete merged branches? (y/N): " -n 1 -r
    print_line ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      logger_info "Cancelled - no branches deleted"
      exit 0
    fi
  fi
  
  # Output results as JSON
  json_build \
    j local_branches "$local_analysis" \
    j remote_branches "$remote_analysis"
}

main "$@"
