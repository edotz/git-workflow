#!/usr/bin/env bash
# Git Branch Cleanup Module
# Identifies merged, stale, and safe-to-delete branches; a squash-merged branch counts as merged
# when git cherry finds no commit of it that is not applied to the main branch (also as one squashed commit), or a
# merged pull request has it as its head
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
source "${PLUGIN_ROOT}/bin/lib/tool.sh"
source "${PLUGIN_ROOT}/bin/lib/remote.sh"

# ============================================
# Configuration
# ============================================
readonly MAIN_BRANCH="${GIT_WORKFLOW_MAIN_BRANCH:-master}"
readonly RELEASE_BRANCH="${GIT_WORKFLOW_RELEASE_BRANCH:-master}"
readonly STALE_DAYS="${PLUGIN_EDOTZ_GIT_WORKFLOW_STALE_DAYS:-30}"

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

# Check if every commit of a branch is applied to the base branch: merge, rebase, or a squash merge. A squash of
# several commits is found by comparing the tree of the branch, as one commit on the merge base, with the base.
# Args: $1 - branch ref, $2 - base ref
# Returns: 0 if merged, 1 otherwise (also when git cannot tell)
is_merged() {
  local ref="$1"
  local base="$2"
  local cherry merge_base tree squash

  cherry=$(git cherry "$base" "$ref" 2>/dev/null) || return 1
  if [[ $'\n'"$cherry" != *$'\n+ '* ]]; then
    return 0
  fi

  merge_base=$(git merge-base "$base" "$ref" 2>/dev/null) || return 1
  tree=$(git rev-parse "${ref}^{tree}" 2>/dev/null) || return 1
  squash=$(git -c user.name=branch-cleanup -c user.email=branch-cleanup@localhost commit-tree "$tree" -p "$merge_base" -m squash 2>/dev/null) || return 1
  cherry=$(git cherry "$base" "$squash" 2>/dev/null) || return 1
  [[ $'\n'"$cherry" != *$'\n+ '* ]]
}

# Set the slug and the developer token the merged pull request lookup needs; both stay empty without a login or a
# remote, and the lookup is then skipped.
# Args: none
init_pr_lookup() {
  PR_LOOKUP_SLUG=""
  PR_LOOKUP_TOKEN=""
  if ! command -v gh >/dev/null 2>&1; then
    return 0
  fi
  PR_LOOKUP_TOKEN=$(gh auth token 2>/dev/null || true)
  if [[ -n "$PR_LOOKUP_TOKEN" ]]; then
    PR_LOOKUP_SLUG=$(remote_slug 2>/dev/null) || PR_LOOKUP_SLUG=""
  fi
  return 0
}

# Check if a merged pull request exists for the branch (gh through tool_run, with the developer token)
# Args: $1 - branch name without origin/
# Returns: 0 if a merged pull request has this head, 1 otherwise (also without a login, a remote or docker)
is_pr_merged() {
  local branch="$1" count
  if [[ -z "$PR_LOOKUP_SLUG" ]]; then
    return 1
  fi
  count=$(GH_TOKEN="$PR_LOOKUP_TOKEN" tool_run gh pr list --repo "$PR_LOOKUP_SLUG" --state merged --head "$branch" --json number --jq length </dev/null 2>/dev/null) || return 1
  [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]
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

  # A squash merge made on GitHub is on origin/<main> until the developer pulls.
  local base="$MAIN_BRANCH"
  if git rev-parse --verify --quiet "origin/${MAIN_BRANCH}" >/dev/null 2>&1; then
    base="origin/${MAIN_BRANCH}"
  fi

  while IFS= read -r branch; do
    # Skip protected branches
    # shellcheck disable=SC2310
    if is_protected "$branch"; then
      continue
    fi
    
    # Check if merged
    # shellcheck disable=SC2310
    if is_merged "$branch" "$base" || is_pr_merged "$branch"; then
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
  
  json_build \
    j merged "$(json_array_from_bash "${merged_local[@]}")" \
    j stale "$(json_array_from_bash "${stale_local[@]}")" \
    j active "$(json_array_from_bash "${active_local[@]}")"
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
    # shellcheck disable=SC2310
    if is_merged "origin/$branch" "origin/$MAIN_BRANCH" || is_pr_merged "$branch"; then
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
  
  json_build \
    j merged "$(json_array_from_bash "${merged_remote[@]}")" \
    j stale "$(json_array_from_bash "${stale_remote[@]}")" \
    j active "$(json_array_from_bash "${active_remote[@]}")"
}

# Print the branches of one analysis, one line per branch as "<group>: <prefix><branch>"
# Args: $1 - analysis JSON, $2 - prefix of the branch name
print_branch_lines() {
  local analysis="$1"
  local prefix="$2"
  local line

  while IFS= read -r line; do
    print_line "$line"
  done < <(json_query "$analysis" \
    'to_entries[] | .key as $g | .value[] | "\($g): \($p)\(sub(":[0-9]+$"; ""))"' \
    -r --arg p "$prefix")
}

# Format and display analysis report
# Args: $1 - local analysis JSON, $2 - remote analysis JSON, $3 - local-only, $4 - remote-only
display_report() {
  local local_json="$1"
  local remote_json="$2"
  local local_only="${3:-false}"
  local remote_only="${4:-false}"

  logger_info "Branch Cleanup Report"
  print_line "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ "$remote_only" == "false" ]]; then
    print_branch_lines "$local_json" ""
  fi
  if [[ "$local_only" == "false" ]]; then
    print_branch_lines "$remote_json" "origin/"
  fi

  print_line ""
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
  init_pr_lookup
  
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
  
  local results
  results=$(json_build \
    j local_branches "$local_analysis" \
    j remote_branches "$remote_analysis")

  local merged_count
  merged_count=$(json_query "$results" '[.local_branches.merged, .remote_branches.merged] | map(length) | add')

  if [[ "$merged_count" -eq 0 ]]; then
    logger_success "Repository is clean - no action needed"
    exit 0
  fi

  # Confirmation (unless --force)
  if [[ "$force" == "false" ]]; then
    if [[ ! -t 0 ]]; then
      print_line "Not interactive - use --force to skip the confirmation"
      exit 0
    fi
    print_line "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_prompt "Delete merged branches? (y/N): "
    read -n 1 -r
    print_line ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      print_line "Cancelled - no branches deleted"
      exit 0
    fi
  fi

  print_line "$results"
}

main "$@"
