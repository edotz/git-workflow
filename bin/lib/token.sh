#!/bin/bash
# Installation Token Utility Library
# Requires: core.sh, json.sh, gh, curl
# Provides: token_fetch, token_drop: the installation token of the token service for one repository and one permission
#           set, held in the shell variable GH_TOKEN for tool_run (tool.sh), which passes it to the tool by name.
# State: sets GH_TOKEN without exporting it; nothing is written to a file, a log line or an argument.
# Settings: TOKEN_SERVICE_URL (default http://127.0.0.1:<TOKEN_SERVICE_PORT>), TOKEN_SERVICE_PORT (default 8790).

# Guard against multiple sourcing
if [[ -n "${BU_STATE_TOKEN:-}" ]]; then return 0; fi
BU_STATE_TOKEN=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BU_LIB}/json.sh"

# ============================================
# Token Constants
# ============================================

readonly TOKEN_SERVICE_DEFAULT_PORT=8790
readonly TOKEN_SERVICE_TIMEOUT=20

# ============================================
# Private Helpers
# ============================================

# Escape one value for a double-quoted string of a curl config file.
# Args: $1 - value
# Sets: _TOKEN_QUOTED
_token_curl_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  _TOKEN_QUOTED="${value//\"/\\\"}"
  return 0
}

# ============================================
# Token Functions
# ============================================

# Fetch the installation token for one repository and set GH_TOKEN, not exported (D5: fail closed).
# The developer's token comes from `gh auth token`. The request goes to the token service in one call; curl reads its
# options, the credential header and the body from a pipe, so no token is on a command line or in a file. The request
# never goes through a proxy: the service is local and the header holds the developer's token. Once the login is read,
# any earlier GH_TOKEN is dropped, so a failure of the request leaves no token set. Call it at the top level: a call
# inside $( ) sets the variable in a subshell only.
# Args:
#   $1 - repository as owner/name
#   $2 - permission set the service knows by name (for example contents)
# Sets: GH_TOKEN
# Exits: 1 with the reason (service unreachable, login not accepted, not a member, repository not installed, or the
#        reason the service gave), 2 on missing arguments, 4 when gh or curl is missing
# Example: token_fetch edotz/git-workflow-sandbox contents
token_fetch() {
  local repo="${1:-}" set_name="${2:-}"
  if [[ -z "$repo" || -z "$set_name" ]]; then
    die_with "$BU_EXIT_USAGE" "token_fetch: repository (owner/name) and permission set required"
  fi
  require_command "gh" "install the GitHub CLI and run gh auth login"
  require_command "curl" "install curl"

  local port="${TOKEN_SERVICE_PORT:-$TOKEN_SERVICE_DEFAULT_PORT}"
  local base="${TOKEN_SERVICE_URL:-http://127.0.0.1:${port}}"
  local url="${base%/}/token"

  local developer
  developer=$(gh auth token 2>/dev/null) || developer=""
  if [[ -z "$developer" ]]; then
    die "token: login not accepted: gh has no login, run gh auth login"
  fi

  token_drop

  local body
  body=$(json_object repo "$repo" set "$set_name")
  body=$(json_query "$body" '.' -c)

  local config=""
  _token_curl_quote "$url"
  config+="url = \"${_TOKEN_QUOTED}\""$'\n'
  _token_curl_quote "Authorization: Bearer ${developer}"
  config+="header = \"${_TOKEN_QUOTED}\""$'\n'
  config+='header = "Content-Type: application/json"'$'\n'
  config+='noproxy = "*"'$'\n'
  _token_curl_quote "$body"
  config+="data = \"${_TOKEN_QUOTED}\""$'\n'
  developer=""

  local response
  if ! response=$(printf '%s' "$config" | curl --silent --connect-timeout 5 --max-time "$TOKEN_SERVICE_TIMEOUT" \
    --write-out $'\n%{http_code}' --config - 2>/dev/null); then
    config=""
    die "token: service unreachable: ${base}"
  fi
  config=""

  local status="${response##*$'\n'}"
  local payload="${response%$'\n'*}"
  response=""

  if [[ "$status" != "200" ]]; then
    local reason="" shown
    if json_validate "$payload"; then
      reason=$(json_get "$payload" "error")
    fi
    if [[ -z "$reason" || "$reason" == "null" ]]; then
      reason="no reason given"
    fi
    case "$reason" in
      "login not accepted" | "not a member" | "repository not installed")
        shown="$reason"
        ;;
      *)
        shown="refused by the service: ${reason}"
        ;;
    esac
    die "token: ${shown} (HTTP ${status}, ${repo}, set ${set_name})"
  fi

  local token=""
  if json_validate "$payload"; then
    token=$(json_get "$payload" "token")
  fi
  payload=""
  if [[ -z "$token" || "$token" == "null" ]]; then
    die "token: the service answered without a token (${repo}, set ${set_name})"
  fi

  GH_TOKEN="$token"
  token=""
  logger_debug "token: installation token set for ${repo}, set ${set_name}"
  return 0
}

# Drop the installation token: unset GH_TOKEN, exported or not.
# Args: none
# Sets: GH_TOKEN (unset)
# Example: token_drop
token_drop() {
  unset GH_TOKEN
  return 0
}

return 0
