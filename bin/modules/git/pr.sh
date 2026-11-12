#!/usr/bin/env bash
# Git PR - push the current branch and open the pull request as the developer
# Usage: app git pr [--dry-run] [--draft]
# Settings: GIT_WORKFLOW_MAIN_BRANCH (default: master). The push and the pull request use the token that gh auth token
# prints for the developer, never the App token; a dry run needs no token
# Refuses the main branch, a red minimum check and a title that lint-commit refuses (a dry run too). The title is the
# subject of the only commit of the branch, or the branch name made readable when there are several; the body lists
# the commit subjects, oldest first.
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${PLUGIN_LIB}/tool.sh"
source "${PLUGIN_LIB}/component.sh"
source "${PLUGIN_LIB}/check.sh"
source "${PLUGIN_LIB}/remote.sh"

cli_set_spec \
  name        "${MODULE_NAME:-pr}" \
  description "${MODULE_DESCRIPTION:-Push the current branch and open the pull request as the developer.}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_flag "dry-run" "n" "Print the branch, the title and the body; change nothing"
cli_add_flag "draft"   "d" "Open the pull request as a draft"

# No repository hooks: the shims of a clone call agentic-os, which the tool image lacks, and the checks ran on the host.
_PR_AUTH=(-c "core.hooksPath=/dev/null" -c "credential.helper=" -c "credential.helper=!gh auth git-credential")
_PR_TITLE=""
_PR_BODY=""
_PR_TITLEFILE=""

# ============================================
# Private Helpers
# ============================================

# Remove the file the title is linted from.
_pr_cleanup() {
  if [[ -n "$_PR_TITLEFILE" ]]; then
    rm -f "$_PR_TITLEFILE"
    _PR_TITLEFILE=""
  fi
  return 0
}

# Run the minimum check of every component and refuse on a red one.
_pr_check() {
  local names name red=0
  local -a selected
  names="$(component_names)"
  readarray -t selected <<< "$names"
  for name in "${selected[@]}"; do
    if ! check_minimum "$name"; then
      red=1
    fi
  done
  if [[ "$red" -ne 0 ]]; then
    die "pr: the minimum check is red, nothing was pushed"
  fi
  return 0
}

# Set _PR_TITLE and _PR_BODY from the commits of the branch that the main branch does not have.
# Args: $1 - main branch  $2 - current branch
_pr_text() {
  local main_branch="$1" branch="$2" subjects subject i
  local -a lines
  if ! subjects="$(git_get_commit_messages "${main_branch}..HEAD")"; then
    die_with "$BU_EXIT_NOT_FOUND" "pr: git cannot list the commits of ${main_branch}..HEAD, is the branch ${main_branch} there?"
  fi
  if [[ -z "$subjects" ]]; then
    die "pr: the branch ${branch} has no commit that ${main_branch} lacks"
  fi
  readarray -t lines <<< "$subjects"

  if [[ "${#lines[@]}" -eq 1 ]]; then
    _PR_TITLE="${lines[0]}"
  elif [[ "$branch" == */* ]]; then
    subject="${branch#*/}"
    _PR_TITLE="${branch%%/*}: ${subject//[_-]/ }"
  else
    subject="${branch//[_-]/ }"
    _PR_TITLE="${subject^}"
  fi

  _PR_BODY=""
  i=$((${#lines[@]} - 1))
  while [[ "$i" -ge 0 ]]; do
    _PR_BODY+="- ${lines[$i]}"$'\n'
    i=$((i - 1))
  done
  _PR_BODY="${_PR_BODY%$'\n'}"
  return 0
}

# The squash merge appends " (#N)" to the title and the pull request number is unknown before the pull request exists.
readonly _PR_SQUASH_SUFFIX=" (#9999)"

# Refuse a title that commitlint refuses, with the squash suffix appended; the title is never rewritten, a squash merge puts it on the main branch.
# Reads: _PR_TITLE
_pr_lint_title() {
  local reason
  register_cleanup _pr_cleanup
  _PR_TITLEFILE="$(mktemp)"
  printf '%s%s\n' "$_PR_TITLE" "$_PR_SQUASH_SUFFIX" > "$_PR_TITLEFILE"
  if ! reason="$(bash "${PLUGIN_ROOT}/bin/modules/git/lint-commit.sh" "$_PR_TITLEFILE" 2>&1)"; then
    logger_error "$reason"
    die_with "$BU_EXIT_CONFIG" "pr: the title '${_PR_TITLE}' did not pass commitlint with the squash suffix '${_PR_SQUASH_SUFFIX}' appended, see the reason above, nothing was pushed"
  fi
  return 0
}

# Push the branch and open the pull request, both with the token of the developer.
# Args: $1 - slug (owner/name)  $2 - main branch  $3 - branch  $4 - draft (yes or no)
_pr_open() {
  local slug="$1" main_branch="$2" branch="$3" draft="$4" url
  require_command "gh" "Install the GitHub CLI and run: gh auth login"
  GH_TOKEN="$(gh auth token 2>/dev/null || true)"
  if [[ -z "$GH_TOKEN" ]]; then
    die_with "$BU_EXIT_CONFIG" "pr: no developer login, run: gh auth login"
  fi
  tool_run git "${_PR_AUTH[@]}" push "https://github.com/${slug}.git" "HEAD:refs/heads/${branch}" </dev/null
  print_item ok "push" "$branch"

  local -a args=(gh pr create --repo "$slug" --base "$main_branch" --head "$branch" --title "$_PR_TITLE" --body-file -)
  if [[ "$draft" == "yes" ]]; then
    args+=(--draft)
  fi
  url="$(printf '%s\n' "$_PR_BODY" | tool_run "${args[@]}")"
  print_item ok "pull request" "$url"
  return 0
}

# ============================================
# Main
# ============================================

main() {
  cli_parse "$@"

  local dry="no" draft="no" main_branch branch slug
  if cli_flag_is_set "dry-run"; then dry="yes"; fi
  if cli_flag_is_set "draft"; then draft="yes"; fi
  main_branch="${GIT_WORKFLOW_MAIN_BRANCH:-master}"

  git_ensure_repo
  cd "$PROJECT_ROOT"

  branch="$(git_get_current_branch)"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    die "pr: HEAD is not on a branch"
  fi
  if [[ "$branch" == "$main_branch" ]]; then
    die "pr: the current branch is ${main_branch}, open the pull request from another branch"
  fi

  component_load "${PROJECT_ROOT}/components.yaml"
  _pr_check
  _pr_text "$main_branch" "$branch"
  _pr_lint_title

  if [[ "$dry" == "yes" ]]; then
    print_header "pull request"
    print_item info "branch" "$branch"
    print_item info "title" "$_PR_TITLE"
    print_line "$_PR_BODY"
    return 0
  fi

  slug="$(remote_slug)"
  _pr_open "$slug" "$main_branch" "$branch" "$draft"
  return 0
}

main "$@"
