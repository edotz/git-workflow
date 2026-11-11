#!/bin/bash
# Minimum Check Library
# Requires: core.sh, git.sh, component.sh (plugin), git, commitlint (through bin/modules/git/lint-commit.sh)
# Provides: check_minimum — commit lint of the commits since the latest tag of a component plus the
#           checks the component declares (decision D32); reads HEAD only and writes nothing

# Guard against multiple sourcing
if [[ -n "${BU_STATE_CHECK:-}" ]]; then return 0; fi
BU_STATE_CHECK=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BU_LIB}/git.sh"
source "${BASH_SOURCE[0]%/*}/component.sh"

# Require git command
require_command "git" "Install git: apt-get install git"

# ============================================
# Private Helpers
# ============================================

# Print the latest tag reachable from HEAD in a repository that matches a glob, nothing when there is none.
# Args:
#   $1 - root: repository root
#   $2 - glob: tag pattern (for example "v[0-9]*" or "web/v[0-9]*")
# Returns: tag name (stdout)
_check_latest_tag() {
  local root="${1:-}" glob="${2:-}"
  git -C "$root" describe --tags --abbrev=0 --match "$glob" HEAD 2>/dev/null || true  # out:return
  return 0
}

# ============================================
# Check Functions
# ============================================

# Run the minimum check of a component on HEAD: lint the subject of every commit since the latest tag of
# the component with the conventional commit rule of the plugin (bin/modules/git/lint-commit.sh), then run
# every command of the checks field of the component from the repository root. Every step runs; the output
# names each failing commit and each failing command. Git runs in the repository root of the loaded components,
# whatever the working directory of the caller is. Nothing is written to the repository.
# The tag of the component is "<name>/v<version>" with two or more components and "v<version>" with one;
# a component without a tag lints every commit of HEAD.
# The lint starts one commitlint process per commit (lint-commit.sh takes one message file): accepted cost.
# Args:
#   $1 - component: Component name (components must be loaded with component_load)
# Returns: 0 when every step passes, 1 when any step fails or git cannot list the commits
# Exits: 2 when no component is given or no components are loaded, 3 when PLUGIN_ROOT is not set, 4 on an unknown
#        component
# Example: check_minimum web
check_minimum() {
  local name="${1:-}"
  [[ -n "$name" ]] || die_with "$BU_EXIT_USAGE" "check_minimum: component required"
  [[ -n "${PLUGIN_ROOT:-}" ]] || die_with "$BU_EXIT_CONFIG" "check_minimum: PLUGIN_ROOT is not set"

  local checks prefix root
  checks="$(component_field "$name" checks)" || return $?
  prefix="$(component_tag_prefix "$name")" || return $?
  root="$(component_root)" || return $?
  local -a commands
  readarray -t commands <<< "$checks"

  local tag range
  tag="$(_check_latest_tag "$root" "${prefix}v[0-9]*")"
  range="HEAD"
  if [[ -n "$tag" ]]; then range="${tag}..HEAD"; fi

  local subjects
  if ! subjects="$(cd "$root" && git_get_commit_messages "$range")"; then
    logger_error "git cannot list the commits of ${range} in ${root}"
    return 1
  fi

  local failed=0 subject msg_file
  if [[ -n "$subjects" ]]; then
    msg_file="$(mktemp)"
    while IFS= read -r subject; do
      printf '%s\n' "$subject" > "$msg_file"
      if ! (cd "$PROJECT_ROOT" && "${PLUGIN_ROOT}/bin/modules/git/lint-commit.sh" "$msg_file" </dev/null); then
        logger_error "commit lint failed: ${subject}"
        failed=$((failed + 1))
      fi
    done <<< "$subjects"
    rm -f "$msg_file"
  fi

  local cmd
  for cmd in "${commands[@]}"; do
    if [[ -z "$cmd" ]]; then continue; fi
    if ! (cd "$root" && bash -c "$cmd"); then
      logger_error "check command failed: ${cmd}"
      failed=$((failed + 1))
    fi
  done

  if [[ "$failed" -gt 0 ]]; then
    logger_error "minimum check of '${name}' failed: ${failed} step(s)"
    return 1
  fi
  logger_info "minimum check of '${name}' passed (${range})"
  return 0
}

return 0
