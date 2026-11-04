#!/usr/bin/env bash
# Git Promote - fast-forward the release branch to the commit of a release tag
# Usage: app git promote <tag> (--dry-run | --apply)
# Settings: MAIN_BRANCH and RELEASE_BRANCH (default: PLUGIN_EDOTZ_GIT_WORKFLOW_MAIN_BRANCH and
#           PLUGIN_EDOTZ_GIT_WORKFLOW_RELEASE_BRANCH), TOKEN_SERVICE_URL, TOKEN_SERVICE_PORT
# Decisions: D16, D27, D52 of the concept: the release branch moves to the release commit of a tag, fast-forward only,
#            and never to the head of master
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${PLUGIN_ROOT}/bin/lib/tool.sh"
source "${PLUGIN_ROOT}/bin/lib/token.sh"

cli_set_spec \
  name        "${MODULE_NAME:-promote}" \
  description "${MODULE_DESCRIPTION:-Fast-forward the release branch to the commit of a release tag.}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_flag "dry-run" "n" "Print the commit the release branch would move to; change nothing"
cli_add_flag "apply"   "a" "Push the commit of the tag to the release branch as the App"

readonly PROMOTE_SUBJECT_RE='^chore\(([a-z][a-z0-9-]*)\): release (.+)$'

_PROMOTE_TARGET=""
_PROMOTE_CURRENT=""
_PROMOTE_SLUG=""
_PROMOTE_URL=""
_PROMOTE_AUTH=(-c "credential.helper=" -c "credential.helper=!gh auth git-credential")

# ============================================
# Private Helpers
# ============================================

# Set _PROMOTE_TARGET to the commit of a release tag. A release tag is a tag whose commit is the release commit of
# that tag: its subject reads chore(<component>): release <tag>. Any other tag is refused.
# Args: $1 - tag
_promote_target() {
  local tag="$1" subject
  if ! _PROMOTE_TARGET="$(tool_run git rev-parse --verify --quiet "refs/tags/${tag}^{commit}" </dev/null)"; then
    die_with "$BU_EXIT_NOT_FOUND" "promote: the tag ${tag} does not exist"
  fi
  subject="$(tool_run git log -1 --format=%s "$_PROMOTE_TARGET" </dev/null)"
  if [[ ! "$subject" =~ $PROMOTE_SUBJECT_RE || "${BASH_REMATCH[2]}" != "$tag" ]]; then
    die "promote: ${tag} is not a release tag, its commit reads '${subject}'"
  fi
  return 0
}

# Set _PROMOTE_CURRENT to the commit of the release branch as last fetched, empty when the branch does not exist.
# Args: $1 - release branch
_promote_current() {
  local branch="$1"
  _PROMOTE_CURRENT="$(tool_run git rev-parse --verify --quiet "refs/remotes/origin/${branch}^{commit}" </dev/null)" \
    || _PROMOTE_CURRENT="$(tool_run git rev-parse --verify --quiet "refs/heads/${branch}^{commit}" </dev/null)" \
    || _PROMOTE_CURRENT=""
  return 0
}

# Refuse a move that is not a fast-forward: the commit of the release branch must be an ancestor of the target.
# Args: $1 - release branch  $2 - tag
_promote_require_fast_forward() {
  local branch="$1" tag="$2"
  if [[ -z "$_PROMOTE_CURRENT" ]]; then
    return 0
  fi
  if ! tool_run git merge-base --is-ancestor "$_PROMOTE_CURRENT" "$_PROMOTE_TARGET" </dev/null; then
    die "promote: moving ${branch} to ${tag} is not a fast-forward, ${branch} is at ${_PROMOTE_CURRENT}"
  fi
  return 0
}

# Bring _PROMOTE_CURRENT up to date with the remote: fetch the release branch when it exists there, treat it as
# absent when the remote says so (ls-remote exit 2), stop when the remote cannot be read.
# Args: $1 - release branch
_promote_refresh() {
  local branch="$1" rc=0
  tool_run git "${_PROMOTE_AUTH[@]}" ls-remote --exit-code --heads "$_PROMOTE_URL" "refs/heads/${branch}" </dev/null >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0)
      tool_run git "${_PROMOTE_AUTH[@]}" fetch "$_PROMOTE_URL" "+refs/heads/${branch}:refs/remotes/origin/${branch}" </dev/null
      _promote_current "$branch"
      ;;
    2)
      print_notice "promote: ${branch} does not exist on the remote yet, it is created"
      _PROMOTE_CURRENT=""
      ;;
    *)
      die "promote: cannot read ${_PROMOTE_URL}, the remote answered with ${rc}"
      ;;
  esac
  return 0
}

# Set _PROMOTE_SLUG (owner/name) and _PROMOTE_URL (https) from the remote origin.
_promote_remote() {
  local url
  url="$(tool_run git remote get-url origin </dev/null)" || die "promote: the repository has no remote origin"
  url="${url%.git}"
  case "$url" in
    git@github.com:*) _PROMOTE_SLUG="${url#git@github.com:}" ;;
    ssh://git@github.com/*) _PROMOTE_SLUG="${url#ssh://git@github.com/}" ;;
    https://github.com/*) _PROMOTE_SLUG="${url#https://github.com/}" ;;
    *) die "promote: the remote origin ${url} is not a github.com repository" ;;
  esac
  _PROMOTE_URL="https://github.com/${_PROMOTE_SLUG}.git"
  return 0
}

# ============================================
# Main
# ============================================

main() {
  cli_parse "$@"

  local tag dry="no" apply="no" main_branch release_branch
  tag="$(cli_get_arg 0)"
  if cli_flag_is_set "dry-run"; then dry="yes"; fi
  if cli_flag_is_set "apply"; then apply="yes"; fi
  if [[ -z "$tag" ]]; then
    die_with "$BU_EXIT_USAGE" "promote: the release tag is required"
  fi
  if [[ "$dry" == "$apply" ]]; then
    die_with "$BU_EXIT_USAGE" "promote: give exactly one of --dry-run and --apply"
  fi
  main_branch="${MAIN_BRANCH:-${PLUGIN_EDOTZ_GIT_WORKFLOW_MAIN_BRANCH:-master}}"
  release_branch="${RELEASE_BRANCH:-${PLUGIN_EDOTZ_GIT_WORKFLOW_RELEASE_BRANCH:-master}}"

  git_ensure_repo
  cd "$PROJECT_ROOT"

  if [[ "$release_branch" == "$main_branch" ]]; then
    print_line "The release branch is the main branch ${main_branch}: nothing to promote"
    return 0
  fi

  tool_image_ensure
  _promote_target "$tag"
  _promote_current "$release_branch"
  _promote_require_fast_forward "$release_branch" "$tag"

  if [[ "$_PROMOTE_CURRENT" == "$_PROMOTE_TARGET" ]]; then
    print_line "${release_branch} is at ${tag} already: nothing to promote"
    return 0
  fi

  if [[ "$dry" == "yes" ]]; then
    print_header "promote ${tag}"
    print_item info "commit" "$_PROMOTE_TARGET"
    print_item info "release branch" "${release_branch}, now ${_PROMOTE_CURRENT:-absent}, based on the last fetch"
    return 0
  fi

  _promote_remote
  token_fetch "$_PROMOTE_SLUG" contents
  _promote_refresh "$release_branch"
  _promote_require_fast_forward "$release_branch" "$tag"
  tool_run git "${_PROMOTE_AUTH[@]}" push "$_PROMOTE_URL" "${_PROMOTE_TARGET}:refs/heads/${release_branch}" </dev/null
  tool_run git update-ref "refs/remotes/origin/${release_branch}" "$_PROMOTE_TARGET" </dev/null
  print_item ok "promote" "${release_branch} moved to ${tag} (${_PROMOTE_TARGET})"
  token_drop
  return 0
}

main "$@"
