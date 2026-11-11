#!/bin/bash
# Component Version Library
# Requires: core.sh, strings.sh, json.sh, files.sh, tool.sh, component.sh, docker
# Provides: version_next, version_tag, version_write, version_cliff, version_latest_tag: the next version of a
#           component, its tag, the version files of its release commit, git-cliff with the plugin configuration and
#           the latest tag of a component. No LLM step (D28): git-cliff decides the bump, the CLI composes the
#           pre-release. A component is loaded (component_load) before any call; the calls run from the repository root.
# State: sets _VERSION_BUMPED, _VERSION_COUNTED, _VERSION_READ, _VERSION_PHP_OUT as private results of its helpers.

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
_VERSION_COUNTED=0
_VERSION_READ=""
_VERSION_PHP_OUT=""

# ============================================
# Private Helpers
# ============================================

# Run git-cliff in the tool image with the configuration of the plugin, bin/config/cliff.toml: only feat, fix, perf and
# breaking commits count (D86). The image mounts the repository only, so the file travels over stdin and is written to
# the HOME of the container, which is a tmpfs.
# Args: $@ - the arguments of git-cliff
# Returns: the status of git-cliff; its stdout and stderr pass through
# Example: version_cliff 'web/v1.0.0..HEAD' --bumped-version --include-path 'packages/web/**'
version_cliff() {
  local config="${PLUGIN_ROOT}/bin/config/cliff.toml"
  require_file "$config" "git-cliff configuration of the plugin"
  tool_run sh -c 'cat > "$HOME/cliff.toml" && exec git-cliff --config "$HOME/cliff.toml" "$@"' sh "$@" < "$config"
}

# Print the latest tag of a component that is reachable from a commit; nothing when it has none.
# Args:
#   $1 - component name
#   $2 - which tags: stable (X.Y.Z only, the default) or any (pre-releases too)
#   $3 - commit, optional (default HEAD)
# Returns: the tag on stdout, empty without a tag; always status 0
# Example: version_latest_tag web stable
version_latest_tag() {
  local name="${1:-}" which="${2:-stable}" rev="${3:-HEAD}" prefix tag=""
  [[ -n "$name" ]] || die_with "$BU_EXIT_USAGE" "version_latest_tag: component required"
  prefix="$(component_tag_prefix "$name")" || return $?
  if [[ "$which" == "stable" ]]; then
    tag=$(tool_run git describe --tags --abbrev=0 --match "${prefix}v[0-9]*.[0-9]*.[0-9]*" --exclude "${prefix}v*-*" "$rev" </dev/null 2>/dev/null) || tag=""
  else
    tag=$(tool_run git describe --tags --abbrev=0 --match "${prefix}v*" "$rev" </dev/null 2>/dev/null) || tag=""
  fi
  printf '%s\n' "$tag"  # out:return
  return 0
}

# Print the git-cliff arguments that limit a run to the component: the range first, because --include-path takes
# several values and would swallow it, then one --include-path per resolved directory, so shared code counts for the
# component.
# Args:
#   $1 - component name
#   $2 - range, empty for the whole history
# Sets: _VERSION_ARGS
_version_scope() {
  local name="$1" range="$2" paths dir
  local -a dirs
  _VERSION_ARGS=()
  if [[ -n "$range" ]]; then
    _VERSION_ARGS+=("$range")
  fi
  paths=$(component_paths "$name") || return $?
  mapfile -t dirs <<<"$paths"
  for dir in "${dirs[@]}"; do
    _VERSION_ARGS+=(--include-path "${dir}/**")
  done
  return 0
}

# Count the commits of a component in a range that make a release: git-cliff prints an empty range as the version
# 0.1.0, so "no change" has to be read from the commits, not from the version.
# Args:
#   $1 - component name
#   $2 - range, empty for the whole history
# Sets: _VERSION_COUNTED
_version_counted() {
  local name="$1" range="$2" out
  _version_scope "$name" "$range" || return $?
  out=$(version_cliff "${_VERSION_ARGS[@]}" --context 2>/dev/null) || die_with "$BU_EXIT_CONFIG" "version: git-cliff failed for the component ${name}"
  _VERSION_COUNTED=$(json_query "$out" '[.[].commits[]] | length' -r) || die_with "$BU_EXIT_CONFIG" "version: git-cliff gave no commits list for the component ${name}"
  return 0
}

# Ask git-cliff for the bumped version of a component over a range. The printed version carries the tag prefix, which
# is removed.
# Args:
#   $1 - component name
#   $2 - tag pattern (regular expression)
#   $3 - tag prefix of the component, possibly empty
#   $4 - range, empty for the whole history
# Sets: _VERSION_BUMPED
_version_bump() {
  local name="$1" pattern="$2" prefix="$3" range="$4" out
  _version_scope "$name" "$range" || return $?
  out=$(version_cliff "${_VERSION_ARGS[@]}" --bumped-version --tag-pattern "$pattern" 2>/dev/null) \
    || die_with "$BU_EXIT_CONFIG" "version: git-cliff failed for the component ${name}"
  out="${out#"${prefix}"v}"
  if ! version_valid "$out"; then
    die_with "$BU_EXIT_CONFIG" "version: git-cliff gave no version for the component ${name}: '${out}'"
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
# The base version is what git-cliff returns for the commits after the latest stable tag of the component, one
# --include-path per directory of component_paths; where the tag sits does not matter, and only feat, fix, perf and
# breaking commits count (D86). Without a channel it is the version. With a channel: when the latest tag of the
# component is <base>-<channel>.N, git-cliff counts the line (all tags of the component match); otherwise the line
# starts at <base>-<channel>.1. The counted result must have the shape X.Y.Z-<channel>.N.
# Args:
#   $1 - component name
#   $2 - channel, optional: lower case letters (alpha, beta, rc)
# Returns: the version on stdout; status 1 and no output when no commit of the component that counts is newer than its
#          latest tag
# Exits: 2 on a missing or invalid argument, 3 for a component without versions, a failing git-cliff, a git-cliff
#        result without a version and a pre-release of the wrong shape; never 1, so a caller tells an error from
#        the status 1 of no change
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

  local stable range=""
  stable="$(version_latest_tag "$name" stable)" || return $?
  if [[ -n "$stable" ]]; then
    range="${stable}..HEAD"
  fi
  _version_counted "$name" "$range" || return $?
  if [[ "$_VERSION_COUNTED" -eq 0 ]]; then
    logger_info "version_next: no feat, fix, perf or breaking commit of the component ${name} since ${stable:-the start}"
    return 1
  fi
  _version_bump "$name" "^${prefix}v[0-9]+\\.[0-9]+\\.[0-9]+\$" "$prefix" "$range" || return $?
  local base="$_VERSION_BUMPED"

  if [[ -z "$channel" ]]; then
    printf '%s\n' "$base"  # out:return
    return 0
  fi

  local latest="" line_re="^${prefix}v${base//./\\.}-${channel}\\.[0-9]+\$"
  latest="$(version_latest_tag "$name" any)" || return $?
  if [[ ! "$latest" =~ $line_re ]]; then
    printf '%s\n' "${base}-${channel}.1"  # out:return
    return 0
  fi

  range="${latest}..HEAD"
  _version_counted "$name" "$range" || return $?
  if [[ "$_VERSION_COUNTED" -eq 0 ]]; then
    logger_info "version_next: no feat, fix, perf or breaking commit of the component ${name} since ${latest}"
    return 1
  fi
  _version_bump "$name" "^${prefix}v" "$prefix" "$range" || return $?
  local counted="$_VERSION_BUMPED"
  local shape_re="^[0-9]+\\.[0-9]+\\.[0-9]+-${channel}\\.[0-9]+\$"
  if [[ ! "$counted" =~ $shape_re ]]; then
    die_with "$BU_EXIT_CONFIG" "version_next: expected X.Y.Z-${channel}.N from git-cliff, got '${counted}' (base ${base}, latest tag ${latest})"
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
