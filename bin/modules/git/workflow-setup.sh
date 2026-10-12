#!/usr/bin/env bash
# Git Workflow Setup
# Reads and validates .github/workflow.env, resolves config, builds package matrix for monorepo.
# Usage: bash bin/app git workflow-setup [--apply] [--check]
set -euo pipefail

# ============================================
# Load Libraries
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BU_ROOT}/lib/core.sh"

source "${BU_LIB}/json.sh"
source "${BU_LIB}/config.sh"
source "${PLUGIN_ROOT}/bin/lib/github.sh"
source "${BU_LIB}/cli.sh"
source "${SCRIPT_DIR}/templates/branch-protection.sh"
source "${SCRIPT_DIR}/templates/workflow-callers.sh"
source "${SCRIPT_DIR}/templates/release-please.sh"

# ============================================
# Constants
# ============================================
readonly WORKFLOW_ENV_FILE="${PROJECT_ROOT}/.github/workflow.env"

# Status check key → GitHub display name map
declare -A STATUS_CHECK_DISPLAY_NAMES=(
  [commit-lint]="Validate Conventional Commits"
  [biome]="Biome Code Quality"
  [php-cs-fixer]="PHP-CS-Fixer"
  [shellcheck]="ShellCheck"
  [eslint]="ESLint Code Quality"
)

# ============================================
# Validation Functions
# ============================================

# Require a key is set and non-empty
# Args: $1 - variable name, $2 - context label
require_key() {
  local key="${1:-}"
  local context="${2:-workflow.env}"
  local value="${!key:-}"
  [[ -n "$value" ]] || die "[$context] Missing required key: $key"
}

# Validate WORKFLOW_TYPE value
# Args: $1 - value
validate_workflow_type() {
  local value="${1:-}"
  case "$value" in
    single|monorepo|package) ;;
    *) die "[workflow.env] Invalid WORKFLOW_TYPE='$value'. Must be: single | monorepo | package" ;;
  esac
}

# Validate RELEASE_TYPE value
# Args: $1 - value
validate_release_type() {
  local value="${1:-}"
  case "$value" in
    node|php|simple) ;;
    *) die "[workflow.env] Invalid RELEASE_TYPE='$value'. Must be: node | php | simple" ;;
  esac
}

# Validate STAGE value
# Args: $1 - value
validate_stage() {
  local value="${1:-}"
  case "$value" in
    production|development) ;;
    *) die "[workflow.env] Invalid STAGE='$value'. Must be: production | development" ;;
  esac
}

# ============================================
# Parsing Functions
# ============================================

# Parse comma-separated list into newline-separated items (trimmed, empty items removed)
# Args: $1 - raw comma-separated string
# Returns: newline-separated items
parse_csv() {
  local raw="${1:-}"
  echo "$raw" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' || true
}

# Resolve STATUS_CHECKS keys → display names
# Args: $1 - comma-separated check keys
# Returns: newline-separated display names
resolve_status_check_names() {
  local raw="${1:-}"
  local key
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    local display="${STATUS_CHECK_DISPLAY_NAMES[$key]:-}"
    if [[ -z "$display" ]]; then
      logger_warning "[workflow.env] Unknown STATUS_CHECKS key: '$key' — using as-is"
      echo "$key"  # out:return
    else
      echo "$display"  # out:return
    fi
  done < <(parse_csv "$raw")
}

# Scan PACKAGES_DIR for subdirs containing .github/workflow.env
# Args: $1 - packages dir (relative to PROJECT_ROOT)
# Returns: JSON array of {local_path, split_repository} objects
build_package_matrix() {
  local packages_dir="${1:-}"
  local full_path="${PROJECT_ROOT}/${packages_dir}"

  [[ -d "$full_path" ]] || die "[workflow.env] PACKAGES_DIR='$packages_dir' does not exist at $full_path"

  local json="["
  local first=true
  local pkg_dir

  while IFS= read -r -d '' pkg_dir; do
    local pkg_env="${pkg_dir}/.github/workflow.env"
    [[ -f "$pkg_env" ]] || continue

    local pkg_name
    pkg_name="$(basename "$pkg_dir")"

    local pkg_repo=""
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*REPO_NAME=(.+)$ ]] && pkg_repo="${BASH_REMATCH[1]}" && break
    done < "$pkg_env"

    [[ -n "$pkg_repo" ]] || { logger_warning "No REPO_NAME in $pkg_env — skipping"; continue; }

    local local_path="${packages_dir}/${pkg_name}"
    local split_repository="${REPO_OWNER}/${pkg_repo}"

    [[ "$first" == "true" ]] && first=false || json+=","
    json+="{\"local_path\":\"${local_path}\",\"split_repository\":\"${split_repository}\"}"
  done < <(find "$full_path" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

  json+="]"
  echo "$json"  # out:return
}

# Iterate over each legacy branch (if any) and invoke a callback
# Args: $1 - callback function name; callback receives branch name as $1
for_each_legacy_branch() {
  local callback="${1:-}"
  [[ -z "$callback" ]] && return 0
  [[ -z "$WS_LEGACY_BRANCHES" ]] && return 0
  local branch
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    "$callback" "$branch"
  done < <(parse_csv "$WS_LEGACY_BRANCHES")
}

# ============================================
# Generation Functions
# ============================================

# Render a BP_TMPL_* template variable via env_substitute_vars
# Args: $1 - template variable name (e.g. BP_TMPL_HEADER)
_bp_render() {
  local tmpl_var="${1:-}"
  env_substitute_vars "${!tmpl_var:-}"
}

# Emit the main branch block by composing split templates + injected dynamic lines
# The contexts list and bypass line are multi-line/structured — injected directly
# between the split template halves rather than via envsubst.
# Args: $1 - branch name, $2 - enforce_admins value, $3 - bypass users line,
#       $4 - newline-separated status check display names
_bp_main_branch_block() {
  local branch="${1:-}"
  local enforce_admins="${2:-true}"
  local bypass_users_line="${3:-              users: []}"
  local check_names="${4:-}"

  export BP_BRANCH="$branch"
  export BP_ENFORCE_ADMINS="$enforce_admins"
  _bp_render BP_TMPL_MAIN_BRANCH_TOP

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    printf '              - "%s"\n' "$name"  # out:return
  done <<< "$check_names"
  printf '              - "Stage Guard"\n'  # out:return

  _bp_render BP_TMPL_MAIN_BRANCH_REVIEWS
  printf '%s\n' "$bypass_users_line"  # out:return

  _bp_render BP_TMPL_MAIN_BRANCH_BOTTOM
}

# Generate .github/branch-protection.yaml from loaded WS_* variables
# Requires: load_workflow_env() already called
# Args: $1 - output file path (default: ${PROJECT_ROOT}/.github/branch-protection.yaml)
generate_branch_protection() {
  local out_file="${1:-${PROJECT_ROOT}/.github/branch-protection.yaml}"

  export BP_REPO_OWNER="$WS_REPO_OWNER"
  export BP_REPO_NAME="$WS_REPO_NAME"
  export BP_ADMIN_USER
  BP_ADMIN_USER=$(config_get_bootstrap_value GITHUB_ADMIN)

  local enforce_admins_main="true"
  local bypass_users_line='              users: []'
  if [[ "$WS_STAGE" == "development" ]]; then
    enforce_admins_main="false"
    bypass_users_line="              users: [\"${BP_ADMIN_USER}\"]"
  fi

  {
    _bp_render BP_TMPL_HEADER

    if [[ "$WS_WORKFLOW_TYPE" == "single" || "$WS_WORKFLOW_TYPE" == "monorepo" ]]; then
      _bp_render BP_TMPL_WILDCARD
      _bp_main_branch_block "$WS_MAIN_BRANCH" "$enforce_admins_main" "$bypass_users_line" "$WS_STATUS_CHECK_NAMES"

      export BP_BRANCH="$WS_RELEASE_BRANCH"
      _bp_render BP_TMPL_RELEASE_BRANCH

      _bp_legacy_release() { export BP_BRANCH="$1"; _bp_render BP_TMPL_RELEASE_BRANCH; }
      for_each_legacy_branch _bp_legacy_release

    elif [[ "$WS_WORKFLOW_TYPE" == "package" ]]; then
      _bp_render BP_TMPL_WILDCARD

      export BP_BRANCH="master"
      _bp_render BP_TMPL_RELEASE_BRANCH

      export BP_BRANCH="$WS_RELEASE_BRANCH"
      _bp_render BP_TMPL_RELEASE_BRANCH

      for_each_legacy_branch _bp_legacy_release
    fi

    _bp_render BP_TMPL_FOOTER

  } > "$out_file"

  logger_success "Generated: $out_file"
}

# ============================================
# Workflow Caller Generation
# ============================================

# Render a WF_TMPL_* template variable via env_substitute_vars
# Args: $1 - template variable name (e.g. WF_TMPL_STATUS_CHECKS_HEADER)
_wf_render() {
  local tmpl_var="${1:-}"
  env_substitute_vars "${!tmpl_var:-}"
}

# Write a rendered template to a file, logging on success
# Args: $1 - template var name, $2 - output file path
_wf_write() {
  local tmpl_var="${1:-}"
  local out_file="${2:-}"
  _wf_render "$tmpl_var" > "$out_file"
  logger_success "Generated: $out_file"
}

# Generate status-checks.yml from WS_STATUS_CHECKS keys + STAGE
# Args: $1 - output directory (default: ${PROJECT_ROOT}/.github/workflows)
_generate_status_checks() {
  local out_dir="${1:-${PROJECT_ROOT}/.github/workflows}"
  local out_file="${out_dir}/status-checks.yml"

  export WF_RELEASE_BRANCH="$WS_RELEASE_BRANCH"
  export WF_MAIN_BRANCH="$WS_MAIN_BRANCH"

  {
    _wf_render WF_TMPL_STATUS_CHECKS_HEADER

    local key
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      case "$key" in
        commit-lint)  _wf_render WF_TMPL_JOB_COMMIT_LINT ;;
        biome)        _wf_render WF_TMPL_JOB_BIOME ;;
        php-cs-fixer) _wf_render WF_TMPL_JOB_PHP_CS_FIXER ;;
        shellcheck)   _wf_render WF_TMPL_JOB_SHELLCHECK ;;
        eslint)       _wf_render WF_TMPL_JOB_ESLINT ;;
        *) logger_warning "[workflow-setup] Unknown STATUS_CHECKS key '$key' — skipping job block" ;;
      esac
    done < <(parse_csv "$WS_STATUS_CHECKS")

    _wf_render WF_TMPL_JOB_STAGE_GUARD

  } > "$out_file"

  logger_success "Generated: $out_file"
}

# Set common WF_* export variables from WS_* globals
_wf_export_vars() {
  export WF_REPO_OWNER="$WS_REPO_OWNER"
  export WF_RELEASE_BRANCH="$WS_RELEASE_BRANCH"
  export WF_MAIN_BRANCH="${WS_MAIN_BRANCH:-}"
  export WF_RELEASE_TYPE="$WS_RELEASE_TYPE"
  export WF_PROJECT_TYPE="$WS_PROJECT_TYPE"
  export WF_BACKPORT_FILES="$WS_BACKPORT_FILES"
  export WF_PACKAGE_MATRIX_JSON="${WS_PACKAGE_MATRIX:-}"
  export WF_MONOREPO_REPO="${WS_MONOREPO_REPO:-}"
  export WF_MONOREPO_PACKAGE="${WS_MONOREPO_PACKAGE:-}"
  export WF_PACKAGE_NAME="${WS_PACKAGE_NAME:-}"
  export WF_STAGE="$WS_STAGE"
}

# Generate all workflow caller files from loaded WS_* variables
# Requires: load_workflow_env() already called
# Args: $1 - output directory (default: ${PROJECT_ROOT}/.github/workflows)
generate_workflow_callers() {
  local out_dir="${1:-${PROJECT_ROOT}/.github/workflows}"
  mkdir -p "$out_dir"

  _wf_export_vars

  case "$WS_WORKFLOW_TYPE" in
    single)
      _generate_status_checks "$out_dir"

      if [[ "$WS_SKIP_RELEASE_PIPELINE" != "true" ]]; then
        export WF_RELEASE_BRANCH="$WS_RELEASE_BRANCH"
        _wf_write WF_TMPL_RELEASE_PIPELINE "${out_dir}/release-pipeline-${WS_RELEASE_BRANCH}.yml"

        # post-release only when MAIN != RELEASE (legacy branches skip post-release)
        if [[ "$WS_MAIN_BRANCH" != "$WS_RELEASE_BRANCH" ]]; then
          _wf_write WF_TMPL_POST_RELEASE "${out_dir}/post-release-${WS_RELEASE_BRANCH}.yml"
        fi

        # Per legacy branch: release-pipeline only (no post-release — MAIN==RELEASE for legacy)
        _wf_legacy_release_pipeline() {
          export WF_RELEASE_BRANCH="$1"
          _wf_write WF_TMPL_RELEASE_PIPELINE "${out_dir}/release-pipeline-${1}.yml"
        }
        for_each_legacy_branch _wf_legacy_release_pipeline
      fi
      ;;

    monorepo)
      _generate_status_checks "$out_dir"

      export WF_RELEASE_BRANCH="$WS_RELEASE_BRANCH"
      _wf_write WF_TMPL_MERGE_SPLIT_REPO "${out_dir}/merge-split-repo-${WS_RELEASE_BRANCH}.yml"

      _wf_legacy_merge_split() {
        export WF_RELEASE_BRANCH="$1"
        _wf_write WF_TMPL_MERGE_SPLIT_REPO "${out_dir}/merge-split-repo-${1}.yml"
      }
      for_each_legacy_branch _wf_legacy_merge_split
      ;;

    package)
      export WF_RELEASE_BRANCH="$WS_RELEASE_BRANCH"
      _wf_write WF_TMPL_PKG_RELEASE_PIPELINE "${out_dir}/release-pipeline.yml"
      _wf_write WF_TMPL_PKG_SYNC_TO_MONOREPO "${out_dir}/sync-to-monorepo.yml"

      if [[ "$WS_RELEASE_TYPE" == "node" ]]; then
        _wf_write WF_TMPL_PKG_RELEASE_PUBLISH "${out_dir}/release-publish.yml"
      fi

      _wf_legacy_pkg_release_pipeline() {
        export WF_RELEASE_BRANCH="$1"
        _wf_write WF_TMPL_PKG_RELEASE_PIPELINE "${out_dir}/release-pipeline-${1}.yml"
      }
      for_each_legacy_branch _wf_legacy_pkg_release_pipeline
      ;;
  esac
}

# ============================================
# Release Please Config Generation
# ============================================

# Generate release-please-config.json from loaded WS_* variables
# Only generated for WORKFLOW_TYPE=single or package (never monorepo)
# Requires: load_workflow_env() already called
# Args: $1 - output file path (default: ${PROJECT_ROOT}/release-please-config.json)
generate_release_please_config() {
  local out_file="${1:-${PROJECT_ROOT}/release-please-config.json}"

  export RP_RELEASE_TYPE="$WS_RELEASE_TYPE"
  export RP_PACKAGE_NAME="${WS_PACKAGE_NAME:-}"
  export schema='$schema'

  local tmpl
  if [[ "$WS_RELEASE_TYPE" == "node" ]]; then
    tmpl="RP_TMPL_CONFIG_NODE"
  else
    tmpl="RP_TMPL_CONFIG_OTHER"
  fi

  echo "${!tmpl}" | envsubst '$RP_RELEASE_TYPE $RP_PACKAGE_NAME $schema' > "$out_file"
  logger_success "Generated: $out_file"
}

# ============================================
# Branch Protection Apply
# ============================================

# Apply branch protection rules by calling apply_protection() directly
# Requires: load_workflow_env() already called; generate_branch_protection() already run
apply_branch_protection() {
  logger_info "Applying branch protection rules..."
  source "${SCRIPT_DIR}/branch-protection.sh"
  local config_file="${PROJECT_ROOT}/.github/branch-protection.yaml"
  local log_file="${PROJECT_ROOT}/var/.github/branch-protection.json"
  mkdir -p "${PROJECT_ROOT}/var/.github"
  GH_REPO="${WS_REPO_OWNER}/${WS_REPO_NAME}" apply_protection "$config_file"
  verify_protection "$config_file" > "$log_file" 2>/dev/null || true
  logger_info "Branch protection state written to: var/.github/branch-protection.json"
}

# ============================================
# Init from Template
# ============================================

# Create .github/workflow.env by copying the typed template from edotz.git-workflow.
# Auto-detects REPO_OWNER and REPO_NAME from git remote origin.
# Args: $1 - type: single | monorepo | package
init_workflow_env() {
  local type="${1:-}"
  case "$type" in
    single|monorepo|package) ;;
    *) die "[workflow-setup] Invalid type '${type}'. Must be: single | monorepo | package" ;;
  esac

  local out_file="${PROJECT_ROOT}/.github/workflow.env"
  if [[ -f "$out_file" ]]; then
    die "[workflow-setup] ${out_file} already exists — remove it first or edit it directly"
  fi

  local tmpl_base
  tmpl_base=$(config_get_bootstrap_value GIT_WORKFLOW_TEMPLATES)
  local tmpl="${PROJECT_ROOT}/${tmpl_base}/workflow.env.${type}.example"
  [[ -f "$tmpl" ]] || die "[workflow-setup] Template not found: ${tmpl}"

  local remote_url
  remote_url=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)
  local owner="" repo=""
  if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  fi

  mkdir -p "${PROJECT_ROOT}/.github"
  sed \
    -e "s|^REPO_OWNER=.*|REPO_OWNER=${owner:-my-org}|" \
    -e "s|^REPO_NAME=.*|REPO_NAME=${repo:-my-repo}|" \
    -e "s|^STAGE=.*|STAGE=development|" \
    "$tmpl" > "$out_file"

  logger_success "Created: .github/workflow.env (${type} template)"
  if [[ -z "$owner" || -z "$repo" ]]; then
    logger_warning "Could not detect REPO_OWNER/REPO_NAME from git remote — update them manually"
  fi
  logger_info "Review the file, fill in remaining values, then run: bash \${BU_ROOT}/app git workflow-setup validate"
}

# ============================================
# Pre-flight Check
# ============================================

_CHECK_PASS=0
_CHECK_FAIL=0

_check_record() {
  local label="${1:-}"
  local result="${2:-fail}"
  local detail="${3:-}"
  if [[ "$result" == "pass" ]]; then
    _CHECK_PASS=$(( _CHECK_PASS + 1 ))
    print_format "  PASS  %s\n" "$label"
  else
    _CHECK_FAIL=$(( _CHECK_FAIL + 1 ))
    print_format "  FAIL  %s%s\n" "$label" "${detail:+: $detail}"
  fi
}

_check_file_exists() {
  local file="${1:-}"
  local label="${2:-$file}"
  if [[ ! -f "$file" ]]; then
    _check_record "$label" "fail" "file not found"
  elif [[ ! -s "$file" ]]; then
    _check_record "$label" "fail" "file is empty"
  else
    _check_record "$label" "pass"
  fi
}

_check_json_key() {
  local file="${1:-}"
  local key="${2:-}"
  local label="${3:-${file}[${key}]}"
  if [[ ! -f "$file" ]]; then
    _check_record "$label" "fail" "file not found"
    return
  fi
  local val
  val=$(json_get_file_with_default "$file" "$key" "")
  if [[ -z "$val" || "$val" == "null" ]]; then
    _check_record "$label" "fail" "key missing or empty"
  else
    _check_record "$label" "pass"
  fi
}

_check_release_please_title_pattern() {
  local file="${PROJECT_ROOT}/release-please-config.json"
  if [[ ! -f "$file" ]]; then
    _check_record "release-please-config.json[pull-request-title-pattern]" "fail" "file not found"
    return
  fi
  local pattern
  pattern=$(json_get_file_with_default "$file" 'packages["."]["pull-request-title-pattern"]' "")
  if [[ -z "$pattern" || "$pattern" == "null" ]]; then
    _check_record "release-please-config.json[pull-request-title-pattern]" "fail" "key missing"
  elif [[ "$pattern" != *'${version}'* ]]; then
    _check_record "release-please-config.json[pull-request-title-pattern]" "fail" "missing \${version} (got: $pattern)"
  else
    _check_record "release-please-config.json[pull-request-title-pattern]" "pass"
  fi
}

_check_manifest_tag_sync() {
  local file="${PROJECT_ROOT}/.release-please-manifest.json"
  if [[ ! -f "$file" ]]; then
    _check_record ".release-please-manifest.json" "fail" "file not found"
    return
  fi
  local manifest_version
  manifest_version=$(json_get_file_with_default "$file" '"."' "")
  if [[ -z "$manifest_version" || "$manifest_version" == "null" ]]; then
    _check_record ".release-please-manifest.json[\".\"]" "fail" "key missing"
    return
  fi
  local latest_tag tag_version
  latest_tag=$(git -C "$PROJECT_ROOT" tag --sort=-v:refname 2>/dev/null | head -1)
  tag_version="${latest_tag#v}"
  if [[ -z "$tag_version" ]]; then
    _check_record ".release-please-manifest.json vs git tag" "fail" "no git tags found"
  elif [[ "$manifest_version" != "$tag_version" ]]; then
    _check_record ".release-please-manifest.json vs git tag" "fail" "manifest=$manifest_version tag=$tag_version"
  else
    _check_record ".release-please-manifest.json vs git tag" "pass"
  fi
}

_check_no_open_release_prs() {
  if ! command_exists "gh"; then
    logger_warning "  SKIP  Open release PRs on $WS_RELEASE_BRANCH (gh not available)"
    return
  fi
  local pr_count
  pr_count=$(gh pr list \
    --repo "${WS_REPO_OWNER}/${WS_REPO_NAME}" \
    --base "$WS_RELEASE_BRANCH" \
    --search "release-please" \
    --json number \
    --jq 'length' 2>/dev/null || echo "0")
  if [[ "$pr_count" -gt 0 ]]; then
    _check_record "Open release PRs on $WS_RELEASE_BRANCH" "fail" "$pr_count open release-please PR(s)"
  else
    _check_record "Open release PRs on $WS_RELEASE_BRANCH" "pass"
  fi
}

_check_action_branch_health() {
  github_ensure_authenticated || {
    logger_warning "  SKIP  generate-readme-action health (gh not available or not authenticated)"
    return
  }
  local action_repo action_branch
  action_repo=$(config_get_bootstrap_value GITHUB_README_REPO)
  action_branch=$(config_get_bootstrap_value GITHUB_README_BRANCH)
  local response
  response=$(github_get_file_contents "$action_repo" "dist/templates/${WS_PROJECT_TYPE}.md" "$action_branch" 2>/dev/null || echo "")
  if [[ -z "$response" ]]; then
    _check_record "${action_repo}@${action_branch} dist/templates/${WS_PROJECT_TYPE}.md" "fail" "missing at ${action_branch} HEAD"
  else
    local sha
    sha=$(json_get_with_default "$response" "sha" "")
    _check_record "${action_repo}@${action_branch}" "pass" "SHA: ${sha:0:7}, template: ${WS_PROJECT_TYPE}.md ✓"
  fi
}

_check_drift() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  generate_branch_protection "${tmp_dir}/branch-protection.yaml" >/dev/null 2>&1 || true
  generate_workflow_callers  "$tmp_dir"                          >/dev/null 2>&1 || true
  if [[ "$WS_WORKFLOW_TYPE" != "monorepo" ]] && [[ "$WS_SKIP_RELEASE_PIPELINE" != "true" ]]; then
    generate_release_please_config "${tmp_dir}/release-please-config.json" >/dev/null 2>&1 || true
  fi

  local f on_disk label
  if [[ -f "${tmp_dir}/branch-protection.yaml" ]]; then
    on_disk="${PROJECT_ROOT}/.github/branch-protection.yaml"
    if ! diff -q "$on_disk" "${tmp_dir}/branch-protection.yaml" >/dev/null 2>&1; then
      _check_record ".github/branch-protection.yaml" "fail" "drifted — run /git:workflow-github"
    else
      _check_record ".github/branch-protection.yaml" "pass"
    fi
  fi

  while IFS= read -r -d '' f; do
    label=".github/workflows/$(basename "$f")"
    on_disk="${PROJECT_ROOT}/.github/workflows/$(basename "$f")"
    if [[ ! -f "$on_disk" ]]; then
      _check_record "$label" "fail" "missing — run /git:workflow-github"
    elif ! diff -q "$on_disk" "$f" >/dev/null 2>&1; then
      _check_record "$label" "fail" "drifted — run /git:workflow-github"
    else
      _check_record "$label" "pass"
    fi
  done < <(find "$tmp_dir" -maxdepth 1 -name "*.yml" -print0 2>/dev/null)

  if [[ -f "${tmp_dir}/release-please-config.json" ]]; then
    on_disk="${PROJECT_ROOT}/release-please-config.json"
    if ! diff -q "$on_disk" "${tmp_dir}/release-please-config.json" >/dev/null 2>&1; then
      _check_record "release-please-config.json" "fail" "drifted — run /git:workflow-github"
    else
      _check_record "release-please-config.json" "pass"
    fi
  fi

  rm -rf "$tmp_dir"
}

check_preflight() {
  _CHECK_PASS=0
  _CHECK_FAIL=0

  print_format "Pre-flight check: %s/%s [%s / %s]\n\n" "$WS_REPO_OWNER" "$WS_REPO_NAME" "$WS_WORKFLOW_TYPE" "$WS_STAGE"
  print_line "--- Runtime Prerequisites ---"

  if [[ -d "${PROJECT_ROOT}/var" ]]; then
    _check_record "var/ directory" "pass"
  else
    _check_record "var/ directory" "fail" "missing — create with: mkdir -p var"
  fi

  print_line ""
  print_line "--- Required Files ---"

  _check_record ".github/workflow.env" "pass"

  local cfg="${PROJECT_ROOT}/docs/readme-config.json"
  _check_file_exists "$cfg" "docs/readme-config.json"
  _check_json_key "$cfg" "projectName"        "docs/readme-config.json[projectName]"
  _check_json_key "$cfg" "projectDescription" "docs/readme-config.json[projectDescription]"
  _check_json_key "$cfg" "author"             "docs/readme-config.json[author]"

  if [[ ! -f "${PROJECT_ROOT}/README.md" ]]; then
    _check_file_exists "${PROJECT_ROOT}/docs/README.md" "docs/README.md"
  fi

  if [[ "$WS_WORKFLOW_TYPE" != "monorepo" ]] && [[ "$WS_SKIP_RELEASE_PIPELINE" != "true" ]]; then
    _check_release_please_title_pattern
    _check_file_exists "${PROJECT_ROOT}/.release-please-manifest.json" ".release-please-manifest.json"
    _check_manifest_tag_sync
  fi

  print_line ""
  print_line "--- Release State ---"
  if [[ -n "${WS_RELEASE_BRANCH:-}" ]]; then
    _check_no_open_release_prs
  fi
  if [[ "$WS_WORKFLOW_TYPE" != "monorepo" ]] && [[ -n "${WS_PROJECT_TYPE:-}" ]]; then
    _check_action_branch_health
  fi

  print_line ""
  print_line "--- Generated File Drift ---"
  _check_drift

  print_format "\n"
  local total=$(( _CHECK_PASS + _CHECK_FAIL ))
  if [[ $_CHECK_FAIL -eq 0 ]]; then
    print_format "Pre-flight complete: %s/%s checks passed\n" "$total" "$total"
    return 0
  else
    print_format "Pre-flight complete: %s/%s checks FAILED\n" "$_CHECK_FAIL" "$total"
    return 1
  fi
}

# ============================================
# Main Validation + Load
# ============================================

# Load and validate workflow.env, set derived variables
# Exports: WS_WORKFLOW_TYPE, WS_STAGE, WS_MAIN_BRANCH, WS_RELEASE_BRANCH,
#          WS_RELEASE_TYPE, WS_PROJECT_TYPE, WS_LEGACY_BRANCHES, WS_STATUS_CHECKS,
#          WS_STATUS_CHECK_NAMES, WS_PACKAGE_MATRIX (monorepo only)
load_workflow_env() {
  [[ -f "$WORKFLOW_ENV_FILE" ]] || die "workflow.env not found at $WORKFLOW_ENV_FILE — run /git:workflow-setup to create it"

  env_parse_file "$WORKFLOW_ENV_FILE" "true" "workflow.env" || true

  # Required — all types
  require_key "REPO_OWNER"
  require_key "REPO_NAME"
  require_key "WORKFLOW_TYPE"
  require_key "RELEASE_TYPE"

  validate_workflow_type "$WORKFLOW_TYPE"
  validate_release_type "$RELEASE_TYPE"

  # Required — single + monorepo
  if [[ "$WORKFLOW_TYPE" == "single" || "$WORKFLOW_TYPE" == "monorepo" ]]; then
    require_key "MAIN_BRANCH"
    require_key "RELEASE_BRANCH"
    require_key "STATUS_CHECKS"
  fi

  # Required — monorepo only
  if [[ "$WORKFLOW_TYPE" == "monorepo" ]]; then
    require_key "PACKAGES_DIR"
  fi

  # Required — package only
  if [[ "$WORKFLOW_TYPE" == "package" ]]; then
    require_key "MONOREPO_REPO"
    require_key "MONOREPO_PACKAGE"
  fi

  # Optional with defaults
  export WS_STAGE="${STAGE:-production}"
  validate_stage "$WS_STAGE"
  export WS_SKIP_RELEASE_PIPELINE="${SKIP_RELEASE_PIPELINE:-false}"

  export WS_WORKFLOW_TYPE="$WORKFLOW_TYPE"
  export WS_REPO_OWNER="$REPO_OWNER"
  export WS_REPO_NAME="$REPO_NAME"
  export WS_RELEASE_TYPE="$RELEASE_TYPE"
  export WS_PROJECT_TYPE="${PROJECT_TYPE:-$RELEASE_TYPE}"
  export WS_MAIN_BRANCH="${MAIN_BRANCH:-}"
  export WS_RELEASE_BRANCH="${RELEASE_BRANCH:-}"
  export WS_LEGACY_BRANCHES="${LEGACY_BRANCHES:-}"
  export WS_STATUS_CHECKS="${STATUS_CHECKS:-}"
  export WS_PACKAGES_DIR="${PACKAGES_DIR:-}"
  export WS_MONOREPO_REPO="${MONOREPO_REPO:-}"
  export WS_MONOREPO_PACKAGE="${MONOREPO_PACKAGE:-}"
  export WS_PACKAGE_NAME="${PACKAGE_NAME:-}"
  export WS_BACKPORT_FILES="${BACKPORT_FILES:-}"

  # Resolve status check display names
  if [[ -n "$WS_STATUS_CHECKS" ]]; then
    WS_STATUS_CHECK_NAMES=$(resolve_status_check_names "$WS_STATUS_CHECKS")
    export WS_STATUS_CHECK_NAMES
  fi

  # Build package matrix for monorepo
  if [[ "$WS_WORKFLOW_TYPE" == "monorepo" ]]; then
    WS_PACKAGE_MATRIX=$(build_package_matrix "$WS_PACKAGES_DIR")
    export WS_PACKAGE_MATRIX
  fi

  # Resolve BACKPORT_FILES default per RELEASE_TYPE
  if [[ -z "$WS_BACKPORT_FILES" ]]; then
    case "$WS_RELEASE_TYPE" in
      node)   WS_BACKPORT_FILES="package.json .release-please-manifest.json CHANGELOG.md README.md" ;;
      php)    WS_BACKPORT_FILES="composer.json .release-please-manifest.json CHANGELOG.md README.md" ;;
      simple) WS_BACKPORT_FILES=".release-please-manifest.json CHANGELOG.md" ;;
    esac
    export WS_BACKPORT_FILES
  fi
}

# ============================================
# Main
# ============================================
cli_set_spec \
  name        "${MODULE_NAME:-workflow-setup}" \
  description "${MODULE_DESCRIPTION:-}" \
  version     "${MODULE_VERSION:-1.0.0}"

main() {
  cli_parse "$@"

  local cmd
  if [[ "${CLI_FLAGS[check]:-}" == "true" ]]; then
    cmd="--check"
  elif [[ "${CLI_FLAGS[apply]:-}" == "true" ]]; then
    cmd="--apply"
  elif [[ -n "${CLI_OPTIONS[init]:-}" || "${CLI_FLAGS[init]:-}" == "true" ]]; then
    cmd="--init"
  else
    cmd="$(cli_get_arg 0 "validate")"
  fi

  case "$cmd" in
    --init)
      local type
      type="${CLI_OPTIONS[init]:-$(cli_get_arg 0 "")}"
      [[ -n "$type" ]] || die_with "$BU_EXIT_USAGE" "Usage: workflow-setup --init <type>  (type: single | monorepo | package)"
      init_workflow_env "$type"
      ;;
    validate|--validate)
      load_workflow_env
      logger_success "workflow.env is valid"
      logger_info "  WORKFLOW_TYPE : $WS_WORKFLOW_TYPE"
      logger_info "  STAGE         : $WS_STAGE"
      logger_info "  REPO          : $WS_REPO_OWNER/$WS_REPO_NAME"
      logger_info "  RELEASE_TYPE  : $WS_RELEASE_TYPE"
      logger_info "  RELEASE_BRANCH: $WS_RELEASE_BRANCH"
      if [[ -n "$WS_MAIN_BRANCH" ]]; then logger_info "  MAIN_BRANCH   : $WS_MAIN_BRANCH"; fi
      if [[ -n "$WS_LEGACY_BRANCHES" ]]; then logger_info "  LEGACY        : $WS_LEGACY_BRANCHES"; fi
      if [[ -n "$WS_STATUS_CHECKS" ]]; then logger_info "  STATUS_CHECKS : $WS_STATUS_CHECKS"; fi
      if [[ "$WS_WORKFLOW_TYPE" == "monorepo" ]]; then logger_info "  PACKAGES      : $WS_PACKAGE_MATRIX"; fi
      ;;
    --apply)
      load_workflow_env
      check_preflight || logger_warning "Pre-flight issues above — fix required-file failures manually; drift will be resolved by this apply."
      generate_branch_protection
      generate_workflow_callers
      if [[ "$WS_WORKFLOW_TYPE" != "monorepo" ]] && [[ "$WS_SKIP_RELEASE_PIPELINE" != "true" ]]; then
        generate_release_please_config
      fi
      apply_branch_protection
      ;;
    --check)
      load_workflow_env
      check_preflight || exit 1
      ;;
    *)
      die "Unknown command: $cmd. Usage: workflow-setup [validate|--apply|--check]"
      ;;
  esac
}

main "$@"
