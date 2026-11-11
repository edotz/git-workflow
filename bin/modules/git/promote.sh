#!/usr/bin/env bash
# Git Promote - move the release branch to the commit of a release tag
# Usage: app git promote <tag> --dry-run
#        app git promote <tag> --apply [--confirm <owner/repo>]
# Settings: GIT_WORKFLOW_MAIN_BRANCH and GIT_WORKFLOW_RELEASE_BRANCH (default: master), TOKEN_SERVICE_URL,
#           TOKEN_SERVICE_PORT
# Decisions: D16, D27, D52 of the concept: the release branch moves to the release commit of a tag and never to the
#            head of master, by fast-forward; D81 (modelled on D64): a release branch that exists but is not an ancestor
#            of that commit is baselined, its old head is tagged legacy/pre-promote and the branch is replaced with a
#            lease on that head, only with --confirm <owner/repo>
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${PLUGIN_LIB}/tool.sh"
source "${PLUGIN_LIB}/token.sh"

cli_set_spec \
  name        "${MODULE_NAME:-promote}" \
  description "${MODULE_DESCRIPTION:-Fast-forward the release branch to the commit of a release tag.}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_flag "dry-run" "n" "Print the commit the release branch would move to; change nothing"
cli_add_flag "apply"   "a" "Push the commit of the tag to the release branch as the App"
cli_add_option "confirm" "c" "owner/repo of the repository: needed to replace a release branch that is not an ancestor of the tag" ""

readonly PROMOTE_SUBJECT_RE='^chore\(([a-z][a-z0-9-]*)\): release (.+)$'

_PROMOTE_TARGET=""
_PROMOTE_CURRENT=""
_PROMOTE_MODE=""
_PROMOTE_SLUG=""
_PROMOTE_URL=""
# No repository hooks: the shims of a clone call agentic-os, which the tool image lacks.
_PROMOTE_AUTH=(-c "core.hooksPath=/dev/null" -c "credential.helper=" -c "credential.helper=!gh auth git-credential")

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

# Set _PROMOTE_MODE from the commit of the release branch and the target: create (the branch does not exist), same (it
# is at the target), ff (its commit is an ancestor of the target) or baseline (it is not an ancestor, D81).
# Args: none
_promote_classify() {
  local rc=0
  if [[ -z "$_PROMOTE_CURRENT" ]]; then
    _PROMOTE_MODE="create"
    return 0
  fi
  if [[ "$_PROMOTE_CURRENT" == "$_PROMOTE_TARGET" ]]; then
    _PROMOTE_MODE="same"
    return 0
  fi
  tool_run git merge-base --is-ancestor "$_PROMOTE_CURRENT" "$_PROMOTE_TARGET" </dev/null || rc=$?
  case "$rc" in
    0) _PROMOTE_MODE="ff" ;;
    1) _PROMOTE_MODE="baseline" ;;
    *) die "promote: git merge-base answered with ${rc} for the commit ${_PROMOTE_CURRENT}" ;;
  esac
  return 0
}

# Refuse an apply that would replace the release branch without --confirm.
# Args: $1 - release branch  $2 - tag  $3 - value of --confirm, empty when not given
_promote_require_confirm() {
  local branch="$1" tag="$2" confirm="$3"
  if [[ -z "$confirm" ]]; then
    die_with "$BU_EXIT_USAGE" "promote: moving ${branch} to ${tag} is not a fast-forward, ${branch} is at ${_PROMOTE_CURRENT}: its old head would be kept as legacy/pre-promote and ${branch} replaced; run the dry run, then again with --apply --confirm <owner/repo>"
  fi
  return 0
}

# Push the commit of the tag to the release branch. A branch that is not an ancestor is baselined: its old head is
# tagged legacy/pre-promote, then the branch is replaced with a lease on that head.
# Args: $1 - release branch
_promote_push() {
  local branch="$1"
  local -a lease=()
  if [[ "$_PROMOTE_MODE" == "baseline" ]]; then
    if ! tool_run git "${_PROMOTE_AUTH[@]}" push "$_PROMOTE_URL" "${_PROMOTE_CURRENT}:refs/tags/legacy/pre-promote" </dev/null; then
      die "promote: the tag legacy/pre-promote of ${_PROMOTE_SLUG} could not be pushed, it may exist at another commit: delete or rename it on the remote, then run again"
    fi
    print_item ok "legacy/pre-promote" "the old head ${_PROMOTE_CURRENT} of ${branch} is kept"
    lease=("--force-with-lease=refs/heads/${branch}:${_PROMOTE_CURRENT}")
  fi
  tool_run git "${_PROMOTE_AUTH[@]}" push "${lease[@]}" "$_PROMOTE_URL" "${_PROMOTE_TARGET}:refs/heads/${branch}" </dev/null
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

  local tag dry="no" apply="no" main_branch release_branch confirm
  tag="$(cli_get_arg 0)"
  confirm="$(cli_get_option "confirm")"
  if cli_flag_is_set "dry-run"; then dry="yes"; fi
  if cli_flag_is_set "apply"; then apply="yes"; fi
  if [[ -z "$tag" ]]; then
    die_with "$BU_EXIT_USAGE" "promote: the release tag is required"
  fi
  if [[ "$dry" == "$apply" ]]; then
    die_with "$BU_EXIT_USAGE" "promote: give exactly one of --dry-run and --apply"
  fi
  main_branch="${GIT_WORKFLOW_MAIN_BRANCH:-master}"
  release_branch="${GIT_WORKFLOW_RELEASE_BRANCH:-master}"

  git_ensure_repo
  cd "$PROJECT_ROOT"

  if [[ "$release_branch" == "$main_branch" ]]; then
    print_line "The release branch is the main branch ${main_branch}: nothing to promote"
    return 0
  fi

  tool_image_ensure
  _promote_target "$tag"
  _promote_current "$release_branch"
  _promote_classify

  if [[ "$_PROMOTE_MODE" == "same" ]]; then
    print_line "${release_branch} is at ${tag} already: nothing to promote"
    return 0
  fi

  if [[ "$dry" == "yes" ]]; then
    print_header "promote ${tag}"
    print_item info "commit" "$_PROMOTE_TARGET"
    print_item info "release branch" "${release_branch}, now ${_PROMOTE_CURRENT:-absent}, based on the last fetch"
    if [[ "$_PROMOTE_MODE" == "baseline" ]]; then
      print_item warning "divergence" "${release_branch} is not an ancestor of ${tag}: the apply keeps its old head as legacy/pre-promote and replaces ${release_branch}"
      die "promote: moving ${release_branch} to ${tag} is not a fast-forward, ${release_branch} is at ${_PROMOTE_CURRENT}: run again with --apply --confirm <owner/repo> to baseline it"
    fi
    return 0
  fi

  if [[ "$_PROMOTE_MODE" == "baseline" ]]; then
    _promote_require_confirm "$release_branch" "$tag" "$confirm"
  fi
  _promote_remote
  if [[ -n "$confirm" && "$confirm" != "$_PROMOTE_SLUG" ]]; then
    die_with "$BU_EXIT_USAGE" "promote: --confirm names ${confirm}, the repository is ${_PROMOTE_SLUG}"
  fi
  token_fetch "$_PROMOTE_SLUG" contents
  _promote_refresh "$release_branch"
  _promote_classify
  if [[ "$_PROMOTE_MODE" == "same" ]]; then
    print_line "${release_branch} is at ${tag} already: nothing to promote"
    token_drop
    return 0
  fi
  if [[ "$_PROMOTE_MODE" == "baseline" ]]; then
    _promote_require_confirm "$release_branch" "$tag" "$confirm"
  fi
  _promote_push "$release_branch"
  tool_run git update-ref "refs/remotes/origin/${release_branch}" "$_PROMOTE_TARGET" </dev/null
  print_item ok "promote" "${release_branch} moved to ${tag} (${_PROMOTE_TARGET})"
  token_drop
  return 0
}

main "$@"
