#!/usr/bin/env bash
# Branch Protection Module
# Manages GitHub branch protection rules via declarative YAML configuration
# Uses lib/github.sh for GitHub API operations

set -euo pipefail

# ============================================
# Load Libraries
# ============================================
source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${PLUGIN_ROOT}/bin/lib/github.sh"
source "${BU_LIB}/json.sh"
source "${BU_LIB}/config.sh"

# ============================================
# Configuration
# ============================================
readonly CONFIG_FILE=".github/branch-protection.yaml"

# ============================================
# CLI Specification
# ============================================
cli_set_spec \
  name        "${MODULE_NAME:-branch-protection}" \
  description "${MODULE_DESCRIPTION:-}" \
  version     "${MODULE_VERSION:-2.0.0}"

cli_add_flag "apply" "a" "Apply all protection rules from config to repository"
cli_add_flag "verify" "v" "Verify all branch protection rules from config"
cli_add_flag "remove" "r" "Remove protection rules from all branches in config"
cli_add_option "config-dir" "d" "Config directory (for monorepo support)" ""
cli_add_flag "json" "j" "JSON output format"
cli_add_flag "verbose" "V" "Verbose output"

# ============================================
# Business Logic Functions
# ============================================

# Note: validate_yaml() moved to lib/config.sh (DRY)
# Use: config_validate_yaml "$config_file"

# Resolve config file path
# Args: $1 - optional config directory
# Returns: Full path to config file
get_config_file_path() {
  local config_dir="${1:-}"

  if [[ -n "$config_dir" ]]; then
    # Custom config directory specified
    local custom_path="${config_dir}/${CONFIG_FILE}"
    if [[ ! -f "$custom_path" ]]; then
      die "Configuration file not found: $custom_path"
    fi
    echo "$custom_path"  # out:return
  else
    # Use default location
    if [[ ! -f "$CONFIG_FILE" ]]; then
      die "Configuration file not found: $CONFIG_FILE"
    fi
    echo "$CONFIG_FILE"  # out:return
  fi
}

# Get branches matching a pattern
# Args: $1 - pattern (e.g., "*", "main", "0.x")
#       $2 - newline-separated list of branch names to exclude (optional, used for "*")
# Returns: List of branch names (one per line)
get_branches_for_pattern() {
  local pattern="${1:-}"
  local exclude="${2:-}"
  [[ -n "$pattern" ]] || die "get_branches_for_pattern: pattern required"

  if [[ "$pattern" == "*" ]]; then
    # Get all remote branches for wildcard, excluding explicitly-configured branches
    while IFS= read -r b; do
      if [[ -n "$exclude" ]]; then
        if grep -qxF "$b" <<< "$exclude"; then
          continue
        fi
      fi
      echo "$b"  # out:return
    done < <(git branch -r 2>/dev/null | grep -v 'HEAD' | sed 's|origin/||' | tr -d ' ' || true)
  else
    # Check if exact branch exists
    if git show-ref --verify --quiet "refs/remotes/origin/$pattern" 2>/dev/null; then
      echo "$pattern"  # out:return
    else
      logger_warning "Branch does not exist: $pattern"
      echo ""  # out:return
    fi
  fi
}

# Get current branch protection rules from GitHub
# Args: $1 - branch name
# Returns: JSON object with protection rules
get_branch_protection() {
  local branch="$1"

  logger_debug "Fetching branch protection for: $branch"
  logger_debug "API Method: GET /repos/{owner}/{repo}/branches/$branch/protection"

  github_ensure_authenticated || {
    logger_error "Not authenticated with GitHub. Run: gh auth login"
    return 1
  }

  logger_debug "Calling GitHub API endpoint..."
  local result
  result=$(github_get_branch_protection "$branch") || {
    logger_warning "No protection configured for branch: $branch"
    echo '{}'  # out:return
    return 0
  }

  logger_debug "Successfully fetched protection rules"
  echo "$result"  # out:return
}

# Apply branch protection rules to a single branch
# Args: $1 - branch name, $2 - protection config JSON
# Returns: 0 on success
apply_protection_single() {
  local branch="$1"
  local config="$2"

  logger_info "Applying protection to branch: $branch"
  logger_debug "API Method: PUT /repos/{owner}/{repo}/branches/$branch/protection"
  logger_debug "API Version: 2022-11-28"
  logger_debug "Required Permissions: admin:repo_hook, repo"

  github_ensure_authenticated || {
    logger_error "Not authenticated with GitHub. Run: gh auth login"
    return 1
  }

  logger_debug "Verifying GitHub repository access..."
  local repo
  repo=$(github_get_repo_fullname) || {
    logger_error "Not in a GitHub repository or insufficient permissions"
    return 1
  }
  logger_debug "Repository: $repo"

  if ! github_set_branch_protection "$branch" "$config"; then
    logger_error "Failed to apply branch protection"
    logger_error "Possible causes:"
    logger_error "  - Insufficient permissions (needs admin access)"
    logger_error "  - Invalid JSON structure"
    logger_error "  - Status check context not registered"
    logger_error "See troubleshooting: .github/GITHUB_API_ENDPOINTS.md"
    return 1
  fi

  logger_success "Branch protection applied: $branch"
  return 0
}

# Apply repository-level settings from config (PATCH /repos/{owner}/{name})
# Args: $1 - config file path
#       $2 - owner
#       $3 - repo name
# Returns: 0 on success or if no repository block present (no-op)
apply_repository_settings() {
  local config_file="${1:-}"
  local owner="${2:-}"
  local name="${3:-}"

  [[ -n "$config_file" ]] || die "apply_repository_settings: config file required"
  [[ -n "$owner" ]] || die "apply_repository_settings: owner required"
  [[ -n "$name" ]] || die "apply_repository_settings: name required"

  local settings_json
  settings_json=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .repository | tojson" "$config_file")

  if ! json_validate "$settings_json" 2>/dev/null; then
    logger_debug "No repository settings block found for: $owner/$name — skipping"
    return 0
  fi

  logger_info "Applying repository settings for: $owner/$name"

  local keys
  keys=$(json_keys "$settings_json")
  while IFS= read -r key; do
    logger_info "  $key: $(json_get "$settings_json" "$key")"
  done <<< "$keys"

  github_patch_repo_settings "$owner" "$name" "$settings_json" || {
    logger_warning "Repository settings apply failed (non-fatal)"
    return 0
  }
}

# Verify repository-level settings against live GitHub state
# Args: $1 - config file path
#       $2 - owner
#       $3 - repo name
# Returns: JSON array of per-key PASS/FAIL results, or empty string if no block present
verify_repository_settings() {
  local config_file="${1:-}"
  local owner="${2:-}"
  local name="${3:-}"

  [[ -n "$config_file" ]] || die "verify_repository_settings: config file required"
  [[ -n "$owner" ]] || die "verify_repository_settings: owner required"
  [[ -n "$name" ]] || die "verify_repository_settings: name required"

  local settings_json
  settings_json=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .repository | tojson" "$config_file")

  if ! json_validate "$settings_json" 2>/dev/null; then
    logger_debug "No repository settings block found for: $owner/$name — skipping verify"
    echo ""  # out:return
    return 0
  fi

  logger_info "Verifying repository settings for: $owner/$name"

  local live_json
  live_json=$(github_get_repo_settings "$owner" "$name") || {
    logger_error "Failed to fetch live repository settings"
    return 1
  }

  local results="["
  local first=true
  local keys
  keys=$(json_keys "$settings_json")

  while IFS= read -r key; do
    local expected actual status
    expected=$(json_get "$settings_json" "$key")
    actual=$(json_get_with_default "$live_json" "$key" "null")

    if [[ "$expected" == "$actual" ]]; then
      status="PASS"
    else
      status="FAIL"
    fi

    logger_debug "  $key: expected=$expected actual=$actual [$status]"

    local entry
    entry=$(json_build s key "$key" s expected "$expected" s actual "$actual" s status "$status")

    if [[ "$first" == "true" ]]; then
      first=false
    else
      results+=","
    fi
    results+="$entry"
  done <<< "$keys"

  results+="]"
  echo "$results"  # out:return
}

# Apply all branch protection rules from config
# Args: $1 - config file path
# Returns: 0 on success
apply_protection() {
  local config_file="${1:-}"

  [[ -n "$config_file" ]] || die "apply_protection: config file required"

  # Get current repo info
  local repo
  repo=$(github_get_repo_fullname) || {
    logger_error "Not in a GitHub repository"
    return 1
  }
  local owner="${repo%%/*}"
  local name="${repo##*/}"

  logger_info "Applying branch protection for repository: $owner/$name"

  # Get all branch patterns for this repo
  local branch_count
  branch_count=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches | length" "$config_file")

  if [[ -z "$branch_count" ]] || [[ "$branch_count" == "0" ]]; then
    logger_error "No branch patterns found in config for: $owner/$name"
    return 1
  fi

  logger_info "Found $branch_count branch pattern(s) to apply"

  # Collect explicit (non-wildcard) patterns to exclude from "*" expansion
  local explicit_patterns=""
  local j
  for ((j=0; j<branch_count; j++)); do
    local p
    p=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches[$j].pattern" "$config_file")
    [[ "$p" != "*" ]] && explicit_patterns+="${p}"$'\n'
  done

  local success_count=0
  local fail_count=0

  # Iterate through each branch pattern
  local i
  for ((i=0; i<branch_count; i++)); do
    local pattern
    pattern=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches[$i].pattern" "$config_file")

    logger_info "Processing pattern: $pattern"

    # Get branches matching pattern (exclude explicit branches from wildcard)
    local branches
    branches=$(get_branches_for_pattern "$pattern" "$explicit_patterns")

    if [[ -z "$branches" ]]; then
      logger_warning "No branches found for pattern: $pattern"
      continue
    fi

    # Get protection rules for this pattern
    local protection_config
    protection_config=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches[$i].protection | tojson" "$config_file")

    # Apply protection to each matching branch
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue

      logger_info "Applying protection to branch: $branch (pattern: $pattern)"

      if apply_protection_single "$branch" "$protection_config"; then
        success_count=$(( success_count + 1 ))
      else
        logger_error "Failed to apply protection to: $branch"
        fail_count=$(( fail_count + 1 ))
      fi
    done <<< "$branches"
  done

  logger_info "Branch protection complete: $success_count succeeded, $fail_count failed"

  if [[ $fail_count -gt 0 ]]; then
    return 1
  fi

  logger_success "All branch protections applied successfully"

  # Apply repository-level settings (non-fatal if absent or fails)
  apply_repository_settings "$config_file" "$owner" "$name" || true

  return 0
}

# Remove branch protection rules from a single branch
# Args: $1 - branch name
# Returns: 0 on success
remove_protection_single() {
  local branch="$1"

  logger_warning "Removing protection from branch: $branch"
  logger_debug "API Method: DELETE /repos/{owner}/{repo}/branches/$branch/protection"
  logger_debug "API Version: 2022-11-28"

  github_ensure_authenticated || {
    logger_error "Not authenticated with GitHub. Run: gh auth login"
    return 1
  }

  logger_debug "Calling GitHub API DELETE endpoint..."
  # Use gh CLI to delete protection
  # Note: {owner}/{repo} placeholders are automatically replaced by gh api
  if ! gh api -X DELETE "/repos/{owner}/{repo}/branches/$branch/protection" 2>/dev/null; then
    logger_error "Failed to remove protection"
    logger_error "Possible causes:"
    logger_error "  - Insufficient permissions (needs admin access)"
    logger_error "  - Branch does not exist"
    logger_error "See troubleshooting: .github/GITHUB_API_ENDPOINTS.md"
    return 1
  fi

  logger_success "Protection removed: $branch"
  return 0
}

# Remove all branch protection rules from config
# Args: $1 - config file path
# Returns: 0 on success
remove_protection() {
  local config_file="${1:-}"

  [[ -n "$config_file" ]] || die "remove_protection: config file required"

  # Get current repo info
  local repo
  repo=$(github_get_repo_fullname) || {
    logger_error "Not in a GitHub repository"
    return 1
  }
  local owner="${repo%%/*}"
  local name="${repo##*/}"

  logger_warning "This will remove protection from all branches in config for: $owner/$name"

  # Get all branch patterns for this repo
  local branch_count
  branch_count=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches | length" "$config_file")

  if [[ -z "$branch_count" ]] || [[ "$branch_count" == "0" ]]; then
    logger_error "No branch patterns found in config for: $owner/$name"
    return 1
  fi

  # Collect explicit (non-wildcard) patterns to exclude from "*" expansion
  local explicit_patterns=""
  local j
  for ((j=0; j<branch_count; j++)); do
    local p
    p=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches[$j].pattern" "$config_file")
    [[ "$p" != "*" ]] && explicit_patterns+="${p}"$'\n'
  done

  # Show branches that will be affected
  logger_info "Branches that will have protection removed:"
  local i
  for ((i=0; i<branch_count; i++)); do
    local pattern
    pattern=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches[$i].pattern" "$config_file")

    local branches
    branches=$(get_branches_for_pattern "$pattern" "$explicit_patterns")

    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      logger_info "  - $branch (pattern: $pattern)"
    done <<< "$branches"
  done

  # Confirmation prompt
  read -p "Continue? (y/N): " -n 1 -r
  print_line ""

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    logger_info "Cancelled"
    return 0
  fi

  local success_count=0
  local fail_count=0

  # Iterate through each branch pattern
  for ((i=0; i<branch_count; i++)); do
    local pattern
    pattern=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches[$i].pattern" "$config_file")

    logger_info "Processing pattern: $pattern"

    # Get branches matching pattern (exclude explicit branches from wildcard)
    local branches
    branches=$(get_branches_for_pattern "$pattern" "$explicit_patterns")

    if [[ -z "$branches" ]]; then
      logger_warning "No branches found for pattern: $pattern"
      continue
    fi

    # Remove protection from each matching branch
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue

      logger_info "Removing protection from branch: $branch (pattern: $pattern)"

      if remove_protection_single "$branch"; then
        success_count=$(( success_count + 1 ))
      else
        logger_error "Failed to remove protection from: $branch"
        fail_count=$(( fail_count + 1 ))
      fi
    done <<< "$branches"
  done

  logger_info "Protection removal complete: $success_count succeeded, $fail_count failed"

  if [[ $fail_count -gt 0 ]]; then
    return 1
  fi

  logger_success "All branch protections removed successfully"
  return 0
}

# Verify protection status for a single branch
# Args: $1 - branch name
# Returns: JSON with verification results
verify_protection_single() {
  local branch="$1"

  logger_debug "Verifying protection status: $branch"
  logger_debug "API Method: GET /repos/{owner}/{repo}/branches/$branch/protection"
  logger_debug "API Version: 2022-11-28"

  local current
  current=$(get_branch_protection "$branch")

  # Determine if protected
  local protected="false"
  if [[ "$current" != "{}" ]] && [[ -n "$current" ]]; then
    protected="true"
  fi

  # Return verification result
  json_build \
    s branch "$branch" \
    b protected "$protected" \
    j rules "$current"
}

# Verify all branch protection rules from config
# Args: $1 - config file path
# Returns: JSON array of verification results
verify_protection() {
  local config_file="${1:-}"

  [[ -n "$config_file" ]] || die "verify_protection: config file required"

  # Get current repo info
  local repo
  repo=$(github_get_repo_fullname) || {
    logger_error "Not in a GitHub repository"
    return 1
  }
  local owner="${repo%%/*}"
  local name="${repo##*/}"

  logger_info "Verifying branch protection for repository: $owner/$name"

  # Get all branch patterns for this repo
  local branch_count
  branch_count=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches | length" "$config_file")

  if [[ -z "$branch_count" ]] || [[ "$branch_count" == "0" ]]; then
    logger_error "No branch patterns found in config for: $owner/$name"
    return 1
  fi

  logger_info "Found $branch_count branch pattern(s) to verify"

  # Collect explicit (non-wildcard) patterns to exclude from "*" expansion
  local explicit_patterns=""
  local j
  for ((j=0; j<branch_count; j++)); do
    local p
    p=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches[$j].pattern" "$config_file")
    [[ "$p" != "*" ]] && explicit_patterns+="${p}"$'\n'
  done

  # Build results array
  local results="["
  local first=true

  # Iterate through each branch pattern
  local i
  for ((i=0; i<branch_count; i++)); do
    local pattern
    pattern=$(yq -r ".repositories[] | select(.owner == \"$owner\" and .name == \"$name\") | .branches[$i].pattern" "$config_file")

    logger_info "Verifying pattern: $pattern"

    # Get branches matching pattern (exclude explicit branches from wildcard)
    local branches
    branches=$(get_branches_for_pattern "$pattern" "$explicit_patterns")

    if [[ -z "$branches" ]]; then
      logger_warning "No branches found for pattern: $pattern"
      continue
    fi

    # Verify each matching branch
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue

      logger_debug "Verifying branch: $branch (pattern: $pattern)"

      local result
      result=$(verify_protection_single "$branch")

      if [[ "$first" == "true" ]]; then
        first=false
      else
        results+=","
      fi
      results+="$result"
    done <<< "$branches"
  done

  results+="]"

  # Append repository-level settings verification if block present
  local repo_verify
  repo_verify=$(verify_repository_settings "$config_file" "$owner" "$name") || true

  if [[ -n "$repo_verify" ]]; then
    echo "{\"branches\":${results},\"repository_settings\":${repo_verify}}"  # out:return
  else
    echo "$results"  # out:return
  fi
}

# ============================================
# Main Function
# ============================================
main() {
  cli_parse "$@"

  # Validate git repository
  git_ensure_repo || die "Not a git repository"

  # Get options
  local apply_mode
  local verify_mode
  local remove_mode
  local json_output
  local verbose_output
  local config_dir

  apply_mode=$(cli_flag_is_set "apply" && echo "true" || echo "false")
  verify_mode=$(cli_flag_is_set "verify" && echo "true" || echo "false")
  remove_mode=$(cli_flag_is_set "remove" && echo "true" || echo "false")
  json_output=$(cli_flag_is_set "json" && echo "true" || echo "false")
  verbose_output=$(cli_flag_is_set "verbose" && echo "true" || echo "false")
  config_dir=$(cli_get_option "config-dir" "")

  # Export for library functions
  export BU_JSON_OUTPUT="$json_output"
  export VERBOSE="$verbose_output"

  local config_file
  config_file=$(get_config_file_path "$config_dir")

  # Convert config file to absolute path
  config_file=$(realpath "$config_file") || die "Failed to resolve config file path: $config_file"
  logger_debug "Using config: $config_file"

  # Validate config (using library function from lib/config.sh)
  # shellcheck disable=SC2310
  config_validate_yaml "$config_file" || die "Invalid configuration"

  # If config-dir specified, extract repository from config and set GH_REPO environment variable
  # This overrides the repository context that gh CLI would normally detect from the current directory
  if [[ -n "$config_dir" ]]; then
    local config_owner
    local config_name
    config_owner=$(yq -r '.repositories[0].owner // ""' "$config_file")
    config_name=$(yq -r '.repositories[0].name // ""' "$config_file")

    if [[ -n "$config_owner" ]] && [[ -n "$config_name" ]]; then
      export GH_REPO="${config_owner}/${config_name}"
      logger_info "Using repository from config: $GH_REPO"
    else
      logger_warning "Could not extract repository from config, using current context"
    fi
  fi

  # Apply mode
  if [[ "$apply_mode" == "true" ]]; then
    logger_info "Applying branch protection configuration"
    logger_debug "Configuration file: $config_file"
    logger_debug "API Endpoint: .github/GITHUB_API_ENDPOINTS.md"

    # shellcheck disable=SC2310
    apply_protection "$config_file" || die "Failed to apply protection"
    exit 0
  fi

  # Verify mode
  if [[ "$verify_mode" == "true" ]]; then
    # shellcheck disable=SC2310
    verify_protection "$config_file" | jq '.' || die "Failed to verify protection"
    exit 0
  fi

  # Remove mode
  if [[ "$remove_mode" == "true" ]]; then
    logger_debug "API Endpoint: .github/GITHUB_API_ENDPOINTS.md"
    # shellcheck disable=SC2310
    remove_protection "$config_file" || die "Failed to remove protection"
    exit 0
  fi

  # Default: verify
  verify_protection "$config_file" | jq '.'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
