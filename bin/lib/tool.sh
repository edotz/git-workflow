#!/bin/bash
# Tool Image Utility Library
# Requires: core.sh, cache/hash.sh, docker
# Provides: tool_image_ensure, tool_run: every tool of the plugin runs in an ephemeral container of the tool image
#           (D20, D35); there is no host-binary fallback.
# State: sets TOOL_IMAGE, the image reference of the current content hash.

# Guard against multiple sourcing
if [[ -n "${BU_STATE_TOOL:-}" ]]; then return 0; fi
BU_STATE_TOOL=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BU_LIB}/cache/hash.sh"

# ============================================
# Tool Constants
# ============================================

readonly TOOL_IMAGE_NAME="edotz-git-workflow-tools"
readonly TOOL_HOME="/tmp/tool-home"
readonly -a TOOL_PIN_KEYS=(
  IMAGE_BASE IMAGE_PLATFORM
  GIT_CLIFF_VERSION GIT_CLIFF_SHA512
  SPLITSH_VERSION SPLITSH_SHA256
  GH_VERSION GH_SHA256
  GIT_APT_VERSION
)

TOOL_IMAGE=""
declare -A _TOOL_PINS=()

# ============================================
# Private Helpers
# ============================================

# Find the repository around a directory without a process: walk up to the first .git entry.
# A linked worktree has a .git file that names its git directory; the common git directory is the one above its
# worktrees/ folder.
# Args: $1 - absolute directory
# Sets: _TOOL_TOP (repository root, or the directory itself when no .git is found), _TOOL_COMMON (common git
#       directory when it lies outside the root, otherwise empty)
_tool_find_repo() {
  local dir="$1" probe="$1" line gitdir
  _TOOL_TOP="$dir"
  _TOOL_COMMON=""
  while true; do
    if [[ -e "${probe}/.git" ]]; then
      _TOOL_TOP="$probe"
      break
    fi
    if [[ -z "$probe" ]]; then
      return 0
    fi
    probe="${probe%/*}"
  done
  if [[ ! -f "${_TOOL_TOP}/.git" ]]; then
    return 0
  fi
  line=$(<"${_TOOL_TOP}/.git")
  gitdir="${line#gitdir:}"
  gitdir="${gitdir# }"
  if [[ "$gitdir" != /* ]]; then
    gitdir=$(cd -P "${_TOOL_TOP}/${gitdir}" && pwd) || die "tool: cannot resolve the git directory ${gitdir}"
  fi
  if [[ "$gitdir" == */worktrees/* ]]; then
    gitdir="${gitdir%/worktrees/*}"
  fi
  if [[ "$gitdir" != "${_TOOL_TOP}"/* ]]; then
    _TOOL_COMMON="$gitdir"
  fi
  return 0
}

# Read the nine pins of the plugin's .env.defaults into _TOOL_PINS.
# env_parse_file is not used: it exports into the environment and skips a key that was set before bootstrap, so a
# pin could differ between a top-level shell and a child process (D24). The pins stay in this array and reach compose
# and docker through local exports only.
# Args: $1 - path of the pins file
# Sets: _TOOL_PINS
_tool_load_pins() {
  local file="$1" line key
  _TOOL_PINS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
      _TOOL_PINS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    fi
  done < "$file"
  for key in "${TOOL_PIN_KEYS[@]}"; do
    if [[ -z "${_TOOL_PINS[$key]:-}" ]]; then
      die "tool: the pin ${key} is missing in ${file}"
    fi
  done
  return 0
}

# ============================================
# Tool Functions
# ============================================

# Load the pins, then make sure the image of the current content hash exists.
# The pins come from .env.defaults in the plugin root only: neither the project .env nor the process environment
# changes them (D24). The project .env and the plugin settings are already loaded by the bootstrap.
# The image is tagged with a hash of the Dockerfile and the pins and is built through .docker/compose.yaml when
# the tag is missing.
# Args: none
# Sets: TOOL_IMAGE, _TOOL_PINS
# Exits: 4 when docker is missing, 1 when a pin is missing or the build fails
# Example: tool_image_ensure
tool_image_ensure() {
  if [[ -n "$TOOL_IMAGE" ]]; then
    return 0
  fi
  require_command "docker" "Docker is a prerequisite of the git-workflow tools: install Docker and start it"
  require_config "PLUGIN_ROOT" "set for the scripts a plugin supplies"

  local pins="${PLUGIN_ROOT}/.env.defaults"
  local dockerfile="${PLUGIN_ROOT}/Dockerfile"
  local compose="${PLUGIN_ROOT}/.docker/compose.yaml"
  require_file "$pins" "tool image pins"
  require_file "$dockerfile" "tool image Dockerfile"
  require_file "$compose" "tool image compose file"

  _tool_load_pins "$pins"

  cache_hash_forget
  cache_hash_files "$dockerfile" "$pins"
  cache_hash_text "${CACHE_HASHES[$dockerfile]}:${CACHE_HASHES[$pins]}"
  local hash="${CACHE_HASH_TEXT:0:12}"
  local image="${TOOL_IMAGE_NAME}:${hash}"

  if ! docker image inspect "$image" >/dev/null 2>&1; then
    logger_info "Building tool image ${image}"
    local key
    for key in "${TOOL_PIN_KEYS[@]}"; do
      local -x "${key}=${_TOOL_PINS[$key]}"
    done
    docker compose -f "$compose" build tools >&2 || die "tool image build failed: ${compose}"
    docker tag "${TOOL_IMAGE_NAME}:${_TOOL_PINS[GIT_CLIFF_VERSION]}-${_TOOL_PINS[GH_VERSION]}" "$image" || die "tool image tag failed: ${image}"
  fi

  TOOL_IMAGE="$image"
  return 0
}

# Run one tool in an ephemeral container of the tool image (D20). The repository around the current directory is
# mounted at its host path, with the common git directory of a linked worktree, and the container runs as the host
# user with a writable HOME and safe.directory set. GH_TOKEN, when set, is passed by variable name: the value never
# appears on the command line and is written nowhere. The image has no entrypoint, so the tool is the command.
# Stdin is forwarded (-i) when it is not a terminal, so `echo '{}' | tool_run jq .` works; a caller inside a
# while-read loop must redirect the call with </dev/null, or the tool consumes the loop input.
# The mounts use --mount, so a colon in a path is safe; a comma in a path is refused.
# Args:
#   $1 - tool: Command name in the image (git, git-cliff, gh, splitsh-lite, jq)
#   $2.. - arguments of the tool
# Returns: Exit status of the tool; its stdout and stderr pass through
# Example: tool_run git rev-parse --is-inside-work-tree
tool_run() {
  local tool="${1:-}"
  [[ -n "$tool" ]] || die "tool_run: tool required"
  shift

  tool_image_ensure

  local cwd="$PWD"
  _tool_find_repo "$cwd"

  local -a args=(run --rm)
  if [[ ! -t 0 ]]; then
    args+=(-i)
  fi
  args+=(
    --platform "${_TOOL_PINS[IMAGE_PLATFORM]}"
    --user "${UID}:${GROUPS[0]}"
    -w "$cwd"
    --tmpfs "${TOOL_HOME}:rw,mode=1777"
    -e "HOME=${TOOL_HOME}"
    -e "GIT_CONFIG_COUNT=1"
    -e "GIT_CONFIG_KEY_0=safe.directory"
    -e "GIT_CONFIG_VALUE_0=*"
  )
  local -a mounts=("$_TOOL_TOP")
  if [[ -n "$_TOOL_COMMON" ]]; then
    mounts+=("$_TOOL_COMMON")
  fi
  local path
  for path in "${mounts[@]}"; do
    if [[ "$path" == *,* ]]; then
      die "tool_run: a comma in the path ${path} cannot be mounted"
    fi
    args+=(--mount "type=bind,src=${path},dst=${path}")
  done
  if [[ -n "${GH_TOKEN:-}" ]]; then
    local -x GH_TOKEN="$GH_TOKEN"
    args+=(-e GH_TOKEN)
  fi

  docker "${args[@]}" "$TOOL_IMAGE" "$tool" "$@"
}

return 0
