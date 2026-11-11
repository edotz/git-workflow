#!/usr/bin/env bash
# Git Release - release the components that changed since their latest tag: a dry run or the apply
# Usage: app git release (--dry-run | --apply) [--draft] [--pre <channel>]
# Settings: GIT_WORKFLOW_MAIN_BRANCH (default: master), TOKEN_SERVICE_URL, TOKEN_SERVICE_PORT
# Decisions: D15, D28, D33, D40 of the concept; D28, D29 of the plan (no LLM step, the README markers)
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${BU_LIB}/files.sh"
source "${PLUGIN_LIB}/tool.sh"
source "${PLUGIN_LIB}/component.sh"
source "${PLUGIN_LIB}/token.sh"
source "${PLUGIN_LIB}/version.sh"
source "${PLUGIN_LIB}/check.sh"

cli_set_spec \
  name        "${MODULE_NAME:-release}" \
  description "${MODULE_DESCRIPTION:-Release the components that changed since their latest tag.}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_flag   "dry-run" "n" "Print per component the next version, the tag, the files and the notes; change nothing"
cli_add_flag   "apply"   "a" "Make the release commit, the tag, the push and the GitHub Release as the App"
cli_add_flag   "draft"   "d" "Leave the GitHub Release unpublished for a person to publish"
cli_add_option "pre"     "p" "Make a pre-release of this channel (lower case letters, for example rc)" ""

readonly RELEASE_README_START='<!-- release:start -->'
readonly RELEASE_README_END='<!-- release:end -->'

# Components to release now: name, prefix, version and tag, index by index.
RELEASE_NAMES=()
RELEASE_PREFIXES=()
RELEASE_VERSIONS=()
RELEASE_TAGS=()
# Components whose release commit is HEAD already: name, prefix and tag; apply makes sure the tag is pushed and
# the GitHub Release exists.
PENDING_NAMES=()
PENDING_PREFIXES=()
PENDING_TAGS=()

_RELEASE_DIRS=()
_RELEASE_CLIFF=()
_RELEASE_NOTES=""
_RELEASE_HOME=""
_RELEASE_README_CHANGED="no"
_RELEASE_SLUG=""
_RELEASE_URL=""
_RELEASE_ID=()
# No repository hooks: the shims of a clone call agentic-os, which the tool image lacks, and the checks ran on the host.
_RELEASE_AUTH=(-c "core.hooksPath=/dev/null" -c "credential.helper=" -c "credential.helper=!gh auth git-credential")

# ============================================
# Private Helpers
# ============================================

# Set _RELEASE_DIRS to the directories of a component and _RELEASE_HOME to the first one, where its CHANGELOG
# and README live.
# Args: $1 - component name
_release_dirs() {
  local paths
  paths="$(component_paths "$1")" || return $?
  mapfile -t _RELEASE_DIRS <<< "$paths"
  _RELEASE_HOME="${_RELEASE_DIRS[0]}"
  return 0
}

# Print the path of a file in the home directory of the component loaded by _release_dirs.
# Args: $1 - file name
# Returns: path relative to the repository root (stdout)
_release_home_file() {
  if [[ "$_RELEASE_HOME" == "." ]]; then
    printf '%s\n' "$1"  # out:return
  else
    printf '%s\n' "${_RELEASE_HOME}/$1"  # out:return
  fi
  return 0
}

# Build the git-cliff arguments of one release in _RELEASE_CLIFF.
# Args:
#   $1 - component name
#   $2 - prefix: tag prefix of the component
#   $3 - tag: the tag of the release
#   $4 - mode: new (the commits since the latest tag, as the release tag) or latest (the notes of the existing tag,
#        without its own release commit)
#   $5 - version: decides the tag pattern, all tags of the component for a pre-release, stable tags otherwise
_release_cliff_args() {
  local name="$1" prefix="$2" tag="$3" mode="$4" version="$5" pattern dir
  _release_dirs "$name" || return $?
  if [[ "$version" == *-* ]]; then
    pattern="^${prefix}v"
  else
    pattern="^${prefix}v[0-9]+\\.[0-9]+\\.[0-9]+\$"
  fi
  _RELEASE_CLIFF=(git-cliff --tag-pattern "$pattern")
  if [[ "$mode" == "new" ]]; then
    _RELEASE_CLIFF+=(--unreleased --tag "$tag")
  else
    local sha
    sha="$(tool_run git rev-parse "refs/tags/${tag}^{commit}" </dev/null)" || die "release: the tag ${tag} does not exist"
    _RELEASE_CLIFF+=(--latest --skip-commit "$sha")
  fi
  for dir in "${_RELEASE_DIRS[@]}"; do
    _RELEASE_CLIFF+=(--include-path "${dir}/**")
  done
  return 0
}

# Set _RELEASE_NOTES to the release notes of git-cliff, without its header.
# Args: the arguments of _release_cliff_args
_release_notes() {
  _release_cliff_args "$@" || return $?
  _RELEASE_NOTES="$(tool_run "${_RELEASE_CLIFF[@]}" --strip header </dev/null 2>/dev/null)" \
    || die "release: git-cliff gave no notes for ${3}"
  return 0
}

# Set _RELEASE_SLUG (owner/name) and _RELEASE_URL (https) from the remote origin.
_release_remote() {
  local url
  url="$(tool_run git remote get-url origin </dev/null)" || die "release: the repository has no remote origin"
  url="${url%.git}"
  case "$url" in
    git@github.com:*) _RELEASE_SLUG="${url#git@github.com:}" ;;
    ssh://git@github.com/*) _RELEASE_SLUG="${url#ssh://git@github.com/}" ;;
    https://github.com/*) _RELEASE_SLUG="${url#https://github.com/}" ;;
    *) die "release: the remote origin ${url} is not a github.com repository" ;;
  esac
  _RELEASE_URL="https://github.com/${_RELEASE_SLUG}.git"
  return 0
}

# Set _RELEASE_ID to the git arguments that give the release commit the identity of the developer. The tool
# image has no global git config, and git.sh has no reader for one, so this is the one raw git call.
_release_identity() {
  local name email
  name="$(git config --get user.name || true)"
  email="$(git config --get user.email || true)"
  if [[ -z "$name" || -z "$email" ]]; then
    die_with "$BU_EXIT_CONFIG" "release: set user.name and user.email in the git config of the developer"
  fi
  _RELEASE_ID=(-c "user.name=${name}" -c "user.email=${email}")
  return 0
}

# Rewrite the lines between the release markers of a README: the version and the link of the release. A README
# without both markers, or without the file, is left alone and the output says so (decision D29 of the plan).
# Args: $1 - file  $2 - version  $3 - tag
# Sets: _RELEASE_README_CHANGED to yes or no
_release_readme() {
  local file="$1" version="$2" tag="$3" content line out="" inside=0 seen=0
  _RELEASE_README_CHANGED="no"
  if [[ ! -f "$file" ]]; then
    print_notice "release: ${file} does not exist, the README is left alone"
    return 0
  fi
  IFS= read -r -d '' content < "$file" || true  # read returns 1 at the end of a file that holds no NUL byte
  while IFS= read -r line; do
    if [[ "$inside" -eq 1 ]]; then
      if [[ "$line" == "$RELEASE_README_END" ]]; then
        out+="${line}"$'\n'
        inside=0
      fi
      continue
    fi
    out+="${line}"$'\n'
    if [[ "$line" == "$RELEASE_README_START" ]]; then
      seen=1
      inside=1
      out+="Version ${version}"$'\n'"[Release ${tag}](https://github.com/${_RELEASE_SLUG}/releases/tag/${tag})"$'\n'
    fi
  done <<< "${content%$'\n'}"
  if [[ "$seen" -eq 0 || "$inside" -eq 1 ]]; then
    print_notice "release: ${file} has no release markers, the README is left alone"
    return 0
  fi
  if [[ "$content" != *$'\n' ]]; then
    out="${out%$'\n'}"
  fi
  write_file_atomic "$file" printf '%s' "$out" || die "release: cannot write ${file}"
  _RELEASE_README_CHANGED="yes"
  return 0
}

# Collect the components to release in the arrays above: a component with a tag on HEAD is pending (a stable tag,
# or any tag when a channel is given, so a pre-release on HEAD does not block the final release), a component with
# a version newer than its latest tag is released, any other releases nothing.
# Args: $1 - channel: pre-release channel or empty
_release_plan() {
  local channel="$1" names_out name versioned prefix tagged version rc
  local -a names
  names_out="$(component_names)" || return $?
  mapfile -t names <<< "$names_out"
  for name in "${names[@]}"; do
    versioned="$(component_field "$name" version)" || return $?
    if [[ "$versioned" != "yes" ]]; then
      continue
    fi
    prefix="$(component_tag_prefix "$name")" || return $?
    if [[ -n "$channel" ]]; then
      tagged="$(tool_run git describe --tags --exact-match --match "${prefix}v*" HEAD </dev/null 2>/dev/null)" || tagged=""
    else
      tagged="$(tool_run git describe --tags --exact-match --match "${prefix}v[0-9]*.[0-9]*.[0-9]*" --exclude "${prefix}v*-*" \
        HEAD </dev/null 2>/dev/null)" || tagged=""
    fi
    if [[ -n "$tagged" ]]; then
      PENDING_NAMES+=("$name")
      PENDING_PREFIXES+=("$prefix")
      PENDING_TAGS+=("$tagged")
      continue
    fi
    if version="$(version_next "$name" "$channel")"; then
      RELEASE_NAMES+=("$name")
      RELEASE_PREFIXES+=("$prefix")
      RELEASE_VERSIONS+=("$version")
      RELEASE_TAGS+=("${prefix}v${version}")
    else
      rc=$?
      if [[ "$rc" -ne 1 ]]; then
        exit "$rc"
      fi
    fi
  done
  return 0
}

# Run the minimum check of every component to release and refuse on a red one.
_release_check() {
  local name red=0
  for name in "${RELEASE_NAMES[@]}"; do
    if ! check_minimum "$name"; then
      red=1
    fi
  done
  if [[ "$red" -ne 0 ]]; then
    die "release: the minimum check is red, nothing was changed"
  fi
  return 0
}

# Print what the release would do, change nothing.
_release_show() {
  local i name prefix version tag files
  for i in "${!RELEASE_NAMES[@]}"; do
    name="${RELEASE_NAMES[$i]}"
    prefix="${RELEASE_PREFIXES[$i]}"
    version="${RELEASE_VERSIONS[$i]}"
    tag="${RELEASE_TAGS[$i]}"
    _release_dirs "$name" || return $?
    files="$(component_field "$name" version_files)" || return $?
    files="${files//$'\n'/, }"
    print_header "release ${name}"
    print_item info "version" "$version"
    print_item info "tag" "$tag"
    print_item info "files" "${files:+${files}, }$(_release_home_file CHANGELOG.md), $(_release_home_file README.md)"
    _release_notes "$name" "$prefix" "$tag" new "$version" || return $?
    print_line "$_RELEASE_NOTES"
  done
  for i in "${!PENDING_NAMES[@]}"; do
    print_header "release ${PENDING_NAMES[$i]}"
    print_item info "pending" "${PENDING_TAGS[$i]} is HEAD: apply makes sure the tag is pushed and the GitHub Release exists"
  done
  return 0
}

# Restore the files a failed release commit left behind: a file in HEAD returns to it, a new file is removed.
# Args: the files of the release commit
_release_rollback() {
  local file
  for file in "$@"; do
    if [[ -z "$file" ]]; then
      continue
    fi
    if tool_run git cat-file -e "HEAD:${file}" </dev/null 2>/dev/null; then
      tool_run git restore --source=HEAD --staged --worktree -- "$file" </dev/null
    else
      tool_run git rm -f -q -- "$file" </dev/null
    fi
  done
  return 0
}

# Write the release commit of one component: version files, CHANGELOG and README, one commit, one tag.
# The commit runs without the hooks of the repository: they run on the host and are not in the tool image, and the
# message is generated and conventional (the minimum check linted the commits before).
# Args: $1 - index into the RELEASE_ arrays
_release_commit() {
  local i="$1" name prefix version tag changelog readme file
  name="${RELEASE_NAMES[$i]}"
  prefix="${RELEASE_PREFIXES[$i]}"
  version="${RELEASE_VERSIONS[$i]}"
  tag="${RELEASE_TAGS[$i]}"
  _release_dirs "$name" || return $?
  changelog="$(_release_home_file CHANGELOG.md)"
  readme="$(_release_home_file README.md)"

  local -a staged
  local files
  files="$(component_field "$name" version_files)" || return $?
  mapfile -t staged <<< "$files"

  version_write "$name" "$version"

  _release_cliff_args "$name" "$prefix" "$tag" new "$version" || return $?
  if [[ ! -f "$changelog" ]]; then
    write_file_atomic "$changelog" printf '' || die "release: cannot create ${changelog}"
  fi
  tool_run "${_RELEASE_CLIFF[@]}" --prepend "$changelog" </dev/null >/dev/null 2>&1 \
    || die "release: git-cliff could not write ${changelog}"
  staged+=("$changelog")

  _release_readme "$readme" "$version" "$tag"
  if [[ "$_RELEASE_README_CHANGED" == "yes" ]]; then
    staged+=("$readme")
  fi

  for file in "${staged[@]}"; do
    if [[ -z "$file" ]]; then
      continue
    fi
    tool_run git add -- "$file" </dev/null
  done
  if ! tool_run git "${_RELEASE_ID[@]}" -c core.hooksPath=/dev/null commit -q -m "chore(${name}): release ${tag}" </dev/null; then
    _release_rollback "${staged[@]}"
    die "release: the release commit failed, the files of the release were restored"
  fi
  tool_run git tag "$tag" </dev/null
  print_item ok "release commit" "chore(${name}): release ${tag}"
  return 0
}

# Push the main branch and one tag.
# Args: $1 - main branch  $2 - tag
_release_push() {
  tool_run git "${_RELEASE_AUTH[@]}" push "$_RELEASE_URL" "HEAD:refs/heads/${1}" "refs/tags/${2}" </dev/null
  print_item ok "push" "${1} and ${2}"
  return 0
}

# Create the GitHub Release of one tag when it does not exist yet.
# The notes are those of the tag, read after the tag exists (mode latest).
# Args: $1 name  $2 prefix  $3 tag  $4 mode (latest)  $5 draft (yes or no)  $6 several (yes or no)
_release_publish() {
  local name="$1" prefix="$2" tag="$3" mode="$4" draft="$5" several="$6" version
  version="${tag#"${prefix}"v}"
  if tool_run gh release view "$tag" --repo "$_RELEASE_SLUG" </dev/null >/dev/null 2>&1; then
    print_item ok "GitHub Release" "${tag} exists"
    return 0
  fi
  _release_notes "$name" "$prefix" "$tag" "$mode" "$version" || return $?
  local -a args=(gh release create "$tag" --repo "$_RELEASE_SLUG" --title "$tag" --notes-file - --verify-tag)
  if [[ "$version" == *-* ]]; then
    args+=(--prerelease)
  fi
  if [[ "$draft" == "yes" ]]; then
    args+=(--draft)
  fi
  if [[ "$several" == "yes" ]]; then
    args+=(--latest=false)
  fi
  printf '%s\n' "$_RELEASE_NOTES" | tool_run "${args[@]}" >/dev/null
  print_item ok "GitHub Release" "${tag} created"
  return 0
}

# Apply: per component the release commit, its push and its GitHub Release, as the App. A component is finished
# before the next one starts, so a failure leaves at most one component half done, and it is the one whose tag
# is on HEAD, which the next apply finds as pending.
# Args: $1 - main branch  $2 - draft (yes or no)
_release_apply() {
  local main_branch="$1" draft="$2" current i several="no" count
  current="$(git_get_current_branch)"
  if [[ "$current" != "$main_branch" ]]; then
    die "release: apply runs on ${main_branch}, the current branch is ${current}"
  fi
  if ! git_is_workdir_clean; then
    die "release: the working tree has uncommitted changes, nothing was changed"
  fi
  count="$(component_names | wc -l)"
  if [[ "$count" -gt 1 ]]; then
    several="yes"
  fi

  _release_remote
  _release_identity
  token_fetch "$_RELEASE_SLUG" contents

  for i in "${!RELEASE_NAMES[@]}"; do
    _release_commit "$i"
    _release_push "$main_branch" "${RELEASE_TAGS[$i]}"
    _release_publish "${RELEASE_NAMES[$i]}" "${RELEASE_PREFIXES[$i]}" "${RELEASE_TAGS[$i]}" latest "$draft" "$several"
  done
  for i in "${!PENDING_NAMES[@]}"; do
    _release_push "$main_branch" "${PENDING_TAGS[$i]}"
    _release_publish "${PENDING_NAMES[$i]}" "${PENDING_PREFIXES[$i]}" "${PENDING_TAGS[$i]}" latest "$draft" "$several"
  done
  token_drop
  return 0
}

# ============================================
# Main
# ============================================

main() {
  cli_parse "$@"

  local dry="no" apply="no" draft="no" channel main_branch
  if cli_flag_is_set "dry-run"; then dry="yes"; fi
  if cli_flag_is_set "apply"; then apply="yes"; fi
  if cli_flag_is_set "draft"; then draft="yes"; fi
  channel="$(cli_get_option "pre")"
  if [[ "$dry" == "$apply" ]]; then
    die_with "$BU_EXIT_USAGE" "release: give exactly one of --dry-run and --apply"
  fi
  main_branch="${GIT_WORKFLOW_MAIN_BRANCH:-master}"

  git_ensure_repo
  cd "$PROJECT_ROOT"
  tool_image_ensure
  component_load "${PROJECT_ROOT}/components.yaml"

  _release_plan "$channel"
  if [[ "${#RELEASE_NAMES[@]}" -eq 0 && "${#PENDING_NAMES[@]}" -eq 0 ]]; then
    print_line "Nothing to release: no component changed since its latest tag"
    return 0
  fi
  _release_check

  if [[ "$dry" == "yes" ]]; then
    _release_show
    return 0
  fi
  _release_apply "$main_branch" "$draft"
  return 0
}

main "$@"
