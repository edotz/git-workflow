#!/bin/bash
# Remote Utility Library
# Requires: core.sh, git.sh, git
# Provides: remote_slug, remote_identity: the repository slug of a remote and the developer identity, both read from
#           the local git configuration only; no token and no tool image.

# Guard against multiple sourcing
if [[ -n "${BU_STATE_REMOTE:-}" ]]; then return 0; fi
BU_STATE_REMOTE=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BU_LIB}/git.sh"

# ============================================
# Remote Functions
# ============================================

# Print the owner/name of a remote. The ssh form git@host:owner/name(.git), the ssh:// form and the https form
# https://host/owner/name(.git) are read; a trailing slash is ignored. The host is not checked.
# Args:
#   $1 - remote name, optional (default origin)
# Returns: owner/name on stdout
# Exits: 4 when the repository has no such remote, 3 when its URL has no owner/name
# Example: slug="$(remote_slug)"
remote_slug() {
  local remote="${1:-origin}" url path
  git_ensure_repo
  url="$(git remote get-url "$remote" 2>/dev/null)" || die_with "$BU_EXIT_NOT_FOUND" "remote: the repository has no remote ${remote}"
  logger_debug "remote: ${remote} is ${url}"

  if [[ "$url" == *://* ]]; then
    path="${url#*://}"
    if [[ "$path" != */* ]]; then
      die_with "$BU_EXIT_CONFIG" "remote: the URL ${url} of the remote ${remote} has no owner/name"
    fi
    path="${path#*/}"
  elif [[ "$url" == *:* ]]; then
    path="${url#*:}"
  else
    die_with "$BU_EXIT_CONFIG" "remote: the URL ${url} of the remote ${remote} has no owner/name"
  fi

  path="${path%%[?#]*}"
  path="${path#/}"
  path="${path%/}"
  path="${path%.git}"
  if [[ ! "$path" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    die_with "$BU_EXIT_CONFIG" "remote: the URL ${url} of the remote ${remote} has no owner/name"
  fi
  echo "$path" # out:return
  return 0
}

# Print the identity of the developer: the value of git config user.name or user.email.
# Args:
#   $1 - which value: name or email
# Returns: the value on stdout
# Exits: 2 for another argument, 3 naming the key when it is unset or empty
# Example: email="$(remote_identity email)"
remote_identity() {
  local which="${1:-}" value
  if [[ "$which" != "name" && "$which" != "email" ]]; then
    die_with "$BU_EXIT_USAGE" "remote_identity: name or email required, got '${which}'"
  fi
  value="$(git config --get "user.${which}" || true)"
  if [[ -z "${value//[[:space:]]/}" ]]; then
    die_with "$BU_EXIT_CONFIG" "remote: git config user.${which} is not set: set it in the git config of the developer"
  fi
  echo "$value" # out:return
  return 0
}

return 0
