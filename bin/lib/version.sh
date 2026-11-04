#!/bin/bash
# Component Version Library
# Requires: core.sh, strings.sh, json.sh, files.sh, tool.sh, component.sh, docker
# Provides: version_next, version_tag, version_write: the next version of a component, its tag and the version
#           files of its release commit. No LLM step (D28): git-cliff decides the bump, the CLI composes the
#           pre-release. A component is loaded (component_load) before any call; the calls run from the repository root.
# State: sets _VERSION_BUMPED, _VERSION_READ, _VERSION_PHP_OUT as private results of its helpers.

# Guard against multiple sourcing
if [[ -n "${BU_STATE_VERSION:-}" ]]; then return 0; fi
BU_STATE_VERSION=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BU_LIB}/strings.sh"
source "${BU_LIB}/json.sh"
source "${BU_LIB}/files.sh"
source "${BASH_SOURCE[0]%/*}/tool.sh"
source "${BASH_SOURCE[0]%/*}/component.sh"

_VERSION_BUMPED=""
_VERSION_READ=""
_VERSION_PHP_OUT=""

# ============================================
# Private Helpers
# ============================================

# Ask git-cliff for the bumped version of a component: one --include-path per resolved directory, so shared code
# counts for the component. The printed version carries the tag prefix, which is removed.
# Args:
#   $1 - component name
#   $2 - tag pattern (regular expression)
#   $3 - tag prefix of the component, possibly empty
# Sets: _VERSION_BUMPED
_version_bump() {
  local name="$1" pattern="$2" prefix="$3" paths dir out
  local -a dirs
  local -a args=(git-cliff --bumped-version --tag-pattern "$pattern")
  paths=$(component_paths "$name") || return $?
  mapfile -t dirs <<<"$paths"
  for dir in "${dirs[@]}"; do
    args+=(--include-path "${dir}/**")
  done
  out=$(tool_run "${args[@]}" </dev/null) || die "version: git-cliff failed for the component ${name}"
  out="${out#"${prefix}"v}"
  if ! version_valid "$out"; then
    die "version: git-cliff gave no version for the component ${name}: '${out}'"
  fi
  _VERSION_BUMPED="$out"
  return 0
}

# Read the version of a file that a version writer handles.
# Args: $1 - file
# Sets: _VERSION_READ
# Exits: 3 when a php file has no or several 'version' lines
_version_read() {
  local file="$1" content line count=0
  local re=$'^([[:space:]]*\'version\'[[:space:]]*=>[[:space:]]*)\'([^\']*)\'(.*)$'
  case "${file##*/}" in
    ext_emconf.php)
      IFS= read -r -d '' content < "$file" || true  # read returns 1 at the end of a file that holds no NUL byte
      _VERSION_READ=""
      while IFS= read -r line; do
        if [[ "$line" =~ $re ]]; then
          _VERSION_READ="${BASH_REMATCH[2]}"
          count=$((count + 1))
        fi
      done <<<"${content%$'\n'}"
      if [[ "$count" -ne 1 ]]; then
        die_with "$BU_EXIT_CONFIG" "version: ${file} holds ${count} 'version' lines, expected exactly one"
      fi
      ;;
    *)
      _VERSION_READ=$(json_get_file_with_default "$file" version "")
      ;;
  esac
  return 0
}

# Rewrite the one 'version' line of an ext_emconf.php, keeping every other byte (indent, comment, line endings).
# Args: $1 - file  $2 - version
# Sets: _VERSION_PHP_OUT, the new content
_version_php_render() {
  local file="$1" version="$2" content line
  local re=$'^([[:space:]]*\'version\'[[:space:]]*=>[[:space:]]*)\'([^\']*)\'(.*)$'
  IFS= read -r -d '' content < "$file" || true  # read returns 1 at the end of a file that holds no NUL byte
  _VERSION_PHP_OUT=""
  while IFS= read -r line; do
    if [[ "$line" =~ $re ]]; then
      line="${BASH_REMATCH[1]}'${version}'${BASH_REMATCH[3]}"
    fi
    _VERSION_PHP_OUT+="${line}"$'\n'
  done <<<"${content%$'\n'}"
  if [[ "$content" != *$'\n' ]]; then
    _VERSION_PHP_OUT="${_VERSION_PHP_OUT%$'\n'}"
  fi
  return 0
}

# ============================================
# Version Functions
# ============================================

# Print the next version of a component, X.Y.Z or X.Y.Z-<channel>.N.
# The base version is what git-cliff returns for the stable tags of the component and one --include-path per
# directory of component_paths. Without a channel it is the version. With a channel: when the latest tag of the
# component is <base>-<channel>.N, git-cliff counts the line (all tags of the component match); otherwise the line
# starts at <base>-<channel>.1. The counted result must have the shape X.Y.Z-<channel>.N.
# Args:
#   $1 - component name
#   $2 - channel, optional: lower case letters (alpha, beta, rc)
# Returns: the version on stdout; status 1 and no output when no commit of the component is newer than its latest tag
# Exits: 2 on a missing or invalid argument, 3 for a component without versions, 1 when git-cliff fails or the
#        pre-release has the wrong shape
# Example: version_next object rc
version_next() {
  local name="${1:-}" channel="${2:-}"
  [[ -n "$name" ]] || die_with "$BU_EXIT_USAGE" "version_next: component required"
  if [[ -n "$channel" && ! "$channel" =~ ^[a-z]+$ ]]; then
    die_with "$BU_EXIT_USAGE" "version_next: the channel is lower case letters, got '${channel}'"
  fi
  local versioned prefix
  versioned="$(component_field "$name" version)" || return $?
  if [[ "$versioned" != "yes" ]]; then
    die_with "$BU_EXIT_CONFIG" "version_next: the component ${name} has version: none"
  fi
  prefix="$(component_tag_prefix "$name")" || return $?
  _version_bump "$name" "^${prefix}v[0-9]+\.[0-9]+\.[0-9]+\$" "$prefix" || return $?
  local base="$_VERSION_BUMPED"

  local stable=""
  stable=$(tool_run git describe --tags --abbrev=0 --match "${prefix}v[0-9]*.[0-9]*.[0-9]*" --exclude "${prefix}v*-*" </dev/null 2>/dev/null) || stable=""
  if [[ "${stable#"${prefix}"v}" == "$base" ]]; then
    logger_info "version_next: no change of the component ${name} since ${stable}"
    return 1
  fi

  if [[ -z "$channel" ]]; then
    printf '%s\n' "$base"  # out:return
    return 0
  fi

  local latest="" line_re="^${prefix}v${base//./\\.}-${channel}\\.[0-9]+\$"
  latest=$(tool_run git describe --tags --abbrev=0 --match "${prefix}v*" </dev/null 2>/dev/null) || latest=""
  if [[ ! "$latest" =~ $line_re ]]; then
    printf '%s\n' "${base}-${channel}.1"  # out:return
    return 0
  fi

  _version_bump "$name" "^${prefix}v" "$prefix" || return $?
  local counted="$_VERSION_BUMPED"
  if [[ "$counted" == "${latest#"${prefix}"v}" ]]; then
    logger_info "version_next: no change of the component ${name} since ${latest}"
    return 1
  fi
  local shape_re="^[0-9]+\\.[0-9]+\\.[0-9]+-${channel}\\.[0-9]+\$"
  if [[ ! "$counted" =~ $shape_re ]]; then
    die "version_next: expected X.Y.Z-${channel}.N from git-cliff, got '${counted}' (base ${base}, latest tag ${latest})"
  fi
  printf '%s\n' "$counted"  # out:return
  return 0
}

# Print the tag of a version: <component>/vX.Y.Z, and vX.Y.Z in a single repository.
# Args:
#   $1 - component name
#   $2 - version, X.Y.Z or X.Y.Z-<channel>.N
# Returns: the tag on stdout
# Exits: 2 on a missing argument or an invalid version
# Example: version_tag web 1.1.0
version_tag() {
  local name="${1:-}" version="${2:-}"
  [[ -n "$name" && -n "$version" ]] || die_with "$BU_EXIT_USAGE" "version_tag: component and version required"
  version_valid "$version" || die_with "$BU_EXIT_USAGE" "version_tag: invalid version '${version}'"
  local prefix
  prefix="$(component_tag_prefix "$name")" || return $?
  printf '%s\n' "${prefix}v${version}"  # out:return
  return 0
}

# Write a version into every file of version_files of a component and read each file back. The files are checked
# first, so a refusal leaves every file untouched. package.json takes the version key; composer.json only when it
# has a version key already; ext_emconf.php only a plain X.Y.Z, in its one 'version' line. A file name without a writer
# is a configuration error. The lockfile of a workspace is never touched (a version change leaves it as it is).
# Args:
#   $1 - component name
#   $2 - version, X.Y.Z or X.Y.Z-<channel>.N
# Exits: 2 on a missing argument or an invalid version, 3 on a refused or unknown file, 4 on a missing file, 1 when
#        a file does not hold the version after the write
# Example: version_write web 1.1.0
version_write() {
  local name="${1:-}" version="${2:-}" files file
  [[ -n "$name" && -n "$version" ]] || die_with "$BU_EXIT_USAGE" "version_write: component and version required"
  version_valid "$version" || die_with "$BU_EXIT_USAGE" "version_write: invalid version '${version}'"
  files=$(component_field "$name" version_files) || return $?
  if [[ -z "$files" ]]; then
    return 0
  fi
  local -a list
  mapfile -t list <<<"$files"

  for file in "${list[@]}"; do
    require_file "$file" "version file of the component ${name}"
    case "${file##*/}" in
      package.json) ;;
      composer.json)
        _version_read "$file"
        if [[ -z "$_VERSION_READ" ]]; then
          die_with "$BU_EXIT_CONFIG" "version: ${file} has no version key, Composer reads the tag: remove it from version_files"
        fi
        ;;
      ext_emconf.php)
        if [[ "$version" == *-* ]]; then
          die_with "$BU_EXIT_CONFIG" "version: ${file} takes plain X.Y.Z versions only, got ${version}"
        fi
        _version_read "$file"
        ;;
      *)
        die_with "$BU_EXIT_CONFIG" "version: no version writer for ${file}"
        ;;
    esac
  done

  for file in "${list[@]}"; do
    case "${file##*/}" in
      ext_emconf.php)
        _version_php_render "$file" "$version"
        write_file_atomic "$file" printf '%s' "$_VERSION_PHP_OUT" || die "version: cannot write ${file}"
        ;;
      *)
        json_file_update "$file" '.version = $v' --arg v "$version" || die "version: cannot write ${file}"
        ;;
    esac
    _version_read "$file"
    if [[ "$_VERSION_READ" != "$version" ]]; then
      die "version: ${file} holds '${_VERSION_READ}' after the write, expected '${version}'"
    fi
    logger_info "Version ${version} written to ${file}"
  done
  return 0
}

return 0
