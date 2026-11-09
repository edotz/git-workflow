#!/usr/bin/env bash
# Git Workflow Status Data Collector
# Collects structured data for the squash-merge workflow: the sync of the release branch with the main branch, and per
# component of components.yaml the latest release tag, the commits since it and the position of the release branch
# against that tag (on, behind, absent). Git runs through tool_run.
# Settings: GIT_WORKFLOW_MAIN_BRANCH and GIT_WORKFLOW_RELEASE_BRANCH (default: master)
# Output: JSON for Claude synthesis

set -euo pipefail

# ============================================
# Load Libraries
# ============================================
source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/git.sh"
source "${BU_LIB}/json.sh"
source "${BU_LIB}/cli.sh"
source "${PLUGIN_ROOT}/bin/lib/tool.sh"
source "${PLUGIN_ROOT}/bin/lib/component.sh"

# ============================================
# Configuration
# ============================================
readonly MAIN_BRANCH="${GIT_WORKFLOW_MAIN_BRANCH:-master}"
readonly RELEASE_BRANCH="${GIT_WORKFLOW_RELEASE_BRANCH:-master}"
readonly PACKAGE_FILE="${PACKAGE_FILE:-package.json}"
readonly DESCRIBE_RE='^(.+)-([0-9]+)-g[0-9a-f]+$'

# The ref the commits are counted from: the main branch, HEAD when the main branch does not exist.
_BASE_REF=""
# The commit of the release branch as last fetched, empty when the branch does not exist.
_RELEASE_COMMIT=""
# One line per component: name, latest release tag, commits since it and the release branch position, tab separated.
_COMPONENT_LINES=()

# ============================================
# Business Logic Functions
# ============================================

# Get current version from package.json
# Args: $1 - package file path (optional, defaults to package.json)
# Returns: Version string or "unknown"
get_current_version() {
  local package_file="${1:-$PACKAGE_FILE}"
  json_get_file_with_default "$package_file" "version" "unknown"  # out:return
}

# Set _BASE_REF and _RELEASE_COMMIT. The release branch is read from the last fetch of origin, then from the local
# branch, the order promote uses; a missing branch leaves _RELEASE_COMMIT empty.
resolve_refs() {
  _BASE_REF="$(tool_run git rev-parse --verify --quiet "refs/heads/${MAIN_BRANCH}^{commit}" </dev/null)" \
    || _BASE_REF="HEAD"
  _RELEASE_COMMIT="$(tool_run git rev-parse --verify --quiet "refs/remotes/origin/${RELEASE_BRANCH}^{commit}" </dev/null)" \
    || _RELEASE_COMMIT="$(tool_run git rev-parse --verify --quiet "refs/heads/${RELEASE_BRANCH}^{commit}" </dev/null)" \
    || _RELEASE_COMMIT=""
  return 0
}

# Get sync status between the main branch and the release branch
# Returns: JSON object with ahead/behind counts, both 0 when the release branch is absent
get_sync_status() {
  local ahead=0 behind=0 counts
  if [[ -n "$_RELEASE_COMMIT" ]]; then
    counts="$(tool_run git rev-list --left-right --count "${_RELEASE_COMMIT}...${_BASE_REF}" </dev/null)" \
      || die "workflow-status: cannot count the commits between ${RELEASE_BRANCH} and ${MAIN_BRANCH}"
    read -r behind ahead <<< "$counts"
  fi
  json_object_num "ahead" "$ahead" "behind" "$behind"  # out:return
}

# Append the status of one component to _COMPONENT_LINES: the latest stable release tag reachable from the base ref
# and the commits since it (all commits of the base ref when no tag exists), and the release branch position:
# on when the tag commit is part of the release branch, behind when the branch lacks it or no release exists yet,
# absent when the branch does not exist.
# Args: $1 - component name
add_component_status() {
  local name="$1" prefix described tag="" count rc=0 position="absent"
  prefix="$(component_tag_prefix "$name")"

  if described="$(tool_run git describe --long --tags --match "${prefix}v[0-9]*.[0-9]*.[0-9]*" \
      --exclude "${prefix}v*-*" "$_BASE_REF" </dev/null 2>/dev/null)" && [[ "$described" =~ $DESCRIBE_RE ]]; then
    tag="${BASH_REMATCH[1]}"
    count="${BASH_REMATCH[2]}"
  else
    count="$(tool_run git rev-list --count "$_BASE_REF" </dev/null)" \
      || die "workflow-status: cannot count the commits of ${_BASE_REF}"
  fi

  if [[ -n "$_RELEASE_COMMIT" ]]; then
    position="behind"
    if [[ -n "$tag" ]]; then
      tool_run git merge-base --is-ancestor "refs/tags/${tag}" "$_RELEASE_COMMIT" </dev/null || rc=$?
      case "$rc" in
        0) position="on" ;;
        1) ;;
        *) die "workflow-status: cannot compare ${tag} with ${RELEASE_BRANCH}, git answered with ${rc}" ;;
      esac
    fi
  fi

  _COMPONENT_LINES+=("${name}"$'\t'"${tag}"$'\t'"${count}"$'\t'"${position}")
  return 0
}

# Assemble complete workflow status
# Returns: JSON object with complete status
get_workflow_status() {
  local current_branch current_version sync_status ahead working_tree
  current_branch="$(git_get_current_branch)"
  current_version="$(get_current_version)"
  sync_status="$(get_sync_status)"
  ahead="$(json_get "$sync_status" "ahead")"
  working_tree="$(git_get_workdir_status)"

  # The counts and the details are built here from one `git log` run in the tool container (tool_run): the
  # framework functions git_get_commit_details and git_conventional_commit_stats run the host git, and the
  # release commit and the base ref are read through the tool too.
  local stats='{}' commits_json='[]' log
  if [[ "$ahead" -gt 0 ]]; then
    log="$(tool_run git log "${_RELEASE_COMMIT}..${_BASE_REF}" --pretty=format:'%H%x1f%h%x1f%an%x1f%ae%x1f%ci%x1f%s' </dev/null)"
    stats="$(json_query null '
      ($log | split("\n") | map(select(length > 0) | split("\u001f")
        | {hash: .[0], short: .[1], author: .[2], email: .[3], date: .[4], message: .[5]})) as $c
      | {feat: [$c[] | select(.message | test("^feat(\\(.*\\))?!?: "))] | length,
         fix: [$c[] | select(.message | test("^fix(\\(.*\\))?!?: "))] | length,
         breaking: [$c[] | select(.message | test("^[a-z]+(\\(.*\\))?!: "))] | length}' -c --arg log "$log")"
    commits_json="$(json_query null '
      $log | split("\n") | map(select(length > 0) | split("\u001f")
        | {hash: .[0], short: .[1], author: .[2], email: .[3], date: .[4], message: .[5]}) | .[:50]' -c --arg log "$log")"
  fi

  local name components_json
  local -a names
  readarray -t names <<< "$(component_names)"
  for name in "${names[@]}"; do
    add_component_status "$name"
  done
  components_json="$(json_query "$(json_array_from_bash "${_COMPONENT_LINES[@]}")" \
    'map(split("\t") | {name: .[0], latest_release: (if .[1] == "" then null else .[1] end),
      commits_since_release: (.[2] | tonumber), release_branch: .[3]})' -c)"

  json_query "null" '{
      current_branch: $branch,
      current_version: $version,
      sync_status: {
        ahead_of_release: $sync.ahead,
        behind_release: $sync.behind
      },
      working_tree: $working_tree,
      unreleased_commits: {
        feat: ($stats.feat // 0),
        fix: ($stats.fix // 0),
        breaking: ($stats.breaking // 0),
        details: $commits
      },
      components: $components
    }' \
    --arg branch "$current_branch" \
    --arg version "$current_version" \
    --argjson sync "$sync_status" \
    --argjson working_tree "$working_tree" \
    --argjson stats "$stats" \
    --argjson commits "$commits_json" \
    --argjson components "$components_json"  # out:return
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

  git_ensure_repo
  cd "$PROJECT_ROOT"

  component_load "${PROJECT_ROOT}/components.yaml"
  resolve_refs
  get_workflow_status
  return 0
}

main "$@"
