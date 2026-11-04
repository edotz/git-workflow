#!/bin/bash
# Component Declaration Library
# Requires: core.sh, yaml.sh, json.sh, jq 1.5+, yq 4.0+
# Provides: component_load, component_names, component_root, component_tag_prefix, component_paths, component_field — the components of
#           components.yaml (repository root), checked against the declaration rules, with defaults
#           (version yes, split no, host github.com); the paths of a workspace component come from pnpm.

# Guard against multiple sourcing
if [[ -n "${BU_STATE_COMPONENT:-}" ]]; then return 0; fi
BU_STATE_COMPONENT=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BU_LIB}/json.sh"
source "${BU_LIB}/yaml.sh"

# ============================================
# State (set by component_load)
# ============================================

# Normalized components as a JSON array, with the defaults applied.
_COMPONENT_JSON=""
# Physical path of the directory that holds the loaded file (the repository root).
_COMPONENT_ROOT=""

# The fields a component may carry, in the order component_field accepts them.
readonly _COMPONENT_FIELDS="name workspace paths version version_files checks split owner repo host"

# One jq program over the whole file: it checks every rule of the declaration and prints either
# "E" and the errors, one per line, or "O" and the normalized components as compact JSON.
readonly _COMPONENT_PROGRAM='
def known: ["name","workspace","paths","version","version_files","checks","split","owner","repo","host"];
def isstr: type == "string" and length > 0;
def strlist: type == "array" and length > 0 and all(.[]; isstr);
def cname($i): if (type == "object" and (.name | isstr)) then "component \u0027" + .name + "\u0027" else "component #" + (($i + 1) | tostring) end;
def given($c; $f): $c | has($f);
def pick($c; $f; $d): if ($c | has($f)) then $c[$f] else $d end;

def top_errors:
  if type != "object" then ["must be a mapping with the key components"]
  else
    ((keys - ["components"]) | map("unknown top-level field \u0027" + . + "\u0027 refused, only components is allowed"))
    + (if (.components | type) != "array" or (.components | length) == 0
       then ["components must be a list with at least one entry"] else [] end)
  end;

def component_errors($i; $count):
  if type != "object" then ["component #\($i + 1): must be a mapping of fields"]
  else
    with_entries(select(.value != null)) as $c
    | ($c | cname($i)) as $l
    | pick($c; "version"; "yes") as $version
    | pick($c; "split"; "no") as $split
    | [
        (if ($c.name | type) != "string" then "name is required"
         elif ($c.name | test("^[a-z][a-z0-9-]*$") | not) then "name must be lower case letters, digits and hyphens, starting with a letter"
         else empty end),
        (if given($c; "workspace") and given($c; "paths") then "exactly one of workspace and paths is allowed, both are given"
         elif (given($c; "workspace") | not) and (given($c; "paths") | not) then "exactly one of workspace and paths is required, neither is given"
         else empty end),
        (if given($c; "workspace") and ($c.workspace | isstr | not) then "workspace must be the name of a package of the pnpm workspace" else empty end),
        (if given($c; "paths") and ($c.paths | strlist | not) then "paths must be a list of directories with at least one entry"
         elif given($c; "paths") and any($c.paths[]; startswith("/") or test("(^|/)\\.\\.(/|$)")) then "paths must be relative to the repository root, without .."
         elif given($c; "paths") and ($c.paths | index(".")) != null and $count > 1 then "path . (the whole repository) is allowed only for the one component of a single repository"
         else empty end),
        (($c | keys) - known | .[] | "unknown field \u0027" + . + "\u0027 refused"),
        (if ($version | IN("yes", "none") | not) then "version must be yes or none" else empty end),
        (if ($split | IN("yes", "no") | not) then "split must be yes or no" else empty end),
        (if ($split != "yes") and (given($c; "owner") or given($c; "repo") or given($c; "host"))
         then "owner, repo and host are refused unless split is yes (given: " + ([("owner", "repo", "host") | select(. as $f | given($c; $f))] | join(", ")) + ")"
         else empty end),
        (if $split == "yes" and $version != "yes" then "split yes needs version yes, because the child repository receives the component tags" else empty end),
        (if $split == "yes" and $count == 1 then "split yes is refused in a single repository, there is nothing to split from" else empty end),
        (if $split == "yes" and (given($c; "owner") | not) then "split yes needs owner" else empty end),
        (if $split == "yes" and (given($c; "repo") | not) then "split yes needs repo" else empty end),
        (("owner", "repo", "host") | select(. as $f | given($c; $f) and ($c[$f] | isstr | not)) | . + " must be a non-empty string"),
        (if given($c; "version_files") and ($c.version_files | type != "array" or any(.[]; isstr | not)) then "version_files must be a list of files" else empty end),
        (if $version == "none" and given($c; "version_files") and ($c.version_files | type == "array" and length > 0) then "version none needs an empty version_files" else empty end),
        (if given($c; "checks") and ($c.checks | type != "array" or any(.[]; isstr | not)) then "checks must be a list of shell commands" else empty end)
      ]
    | map($l + ": " + .)
  end;

def duplicate_errors:
  [.[] | select(type == "object") | .name | select(type == "string")]
  | group_by(.)
  | map(select(length > 1) | "component \u0027" + .[0] + "\u0027: name is not unique, it is declared " + (length | tostring) + " times");

def normalize:
  with_entries(select(.value != null))
  | {
      name,
      workspace: (.workspace // null),
      paths: (.paths // []),
      version: pick(.; "version"; "yes"),
      version_files: (.version_files // []),
      checks: (.checks // []),
      split: pick(.; "split"; "no"),
      owner: (.owner // null),
      repo: (.repo // null),
      host: (.host // "github.com")
    };

top_errors as $top
| (if ($top | length) > 0 then $top
   else (.components | length) as $count
     | [.components | to_entries[] | .key as $i | .value | component_errors($i; $count)[]] + (.components | duplicate_errors)
   end) as $errors
| if ($errors | length) > 0 then "E" + ($errors | join("\n"))
  else "O" + (.components | map(normalize) | tojson)
  end
'

# ============================================
# Private Helpers
# ============================================

# Stop unless component_load ran successfully.
_component_require_loaded() {
  if [[ -z "$_COMPONENT_JSON" ]]; then
    die_with "$BU_EXIT_USAGE" "${1:-component}: no components loaded, call component_load first"
  fi
  return 0
}

# ============================================
# Component Functions
# ============================================

# Read components.yaml, check every rule of the declaration and keep the components with their defaults.
# Prints every violated rule with the component it belongs to and returns 3 (BU_EXIT_CONFIG) when there is one.
# The repository root is the directory of the file.
# Args:
#   $1 - file: components.yaml
# Returns: 0 when the declaration is valid, 3 otherwise (state is cleared)
# Exits: 4 when the file does not exist
# Example: component_load "${PROJECT_ROOT}/components.yaml"
component_load() {
  local file="${1:-}"
  [[ -n "$file" ]] || die_with "$BU_EXIT_USAGE" "component_load: file required"
  require_file "$file" "component declaration"

  _COMPONENT_JSON=""
  _COMPONENT_ROOT=""

  local dir="${file%/*}"
  if [[ "$file" != */* ]]; then dir="."; fi
  local root
  root="$(cd -P "$dir" && pwd -P)"

  local json
  json="$(yaml_to_json "$file")"
  if [[ -z "$json" || "$json" == "null" ]]; then
    print_error "${file}: not a readable YAML mapping"
    return "$BU_EXIT_CONFIG"
  fi

  local result
  result="$(json_query "$json" "$_COMPONENT_PROGRAM")"

  if [[ "${result:0:1}" == "E" ]]; then
    local line
    while IFS= read -r line; do
      print_error "${file}: ${line}"
    done <<< "${result:1}"
    return "$BU_EXIT_CONFIG"
  fi

  _COMPONENT_JSON="${result:1}"
  _COMPONENT_ROOT="$root"
  logger_debug "component_load: ${file} read from ${root}"
  return 0
}

# Print the names of the loaded components, one per line, in file order.
# Returns: names (stdout)
# Example: component_names
component_names() {
  _component_require_loaded "component_names"
  json_query "$_COMPONENT_JSON" '.[].name'  # out:return
}

# Print the repository root of the loaded components: the physical path of the directory that holds the file.
# Returns: path (stdout)
# Example: root="$(component_root)"
component_root() {
  _component_require_loaded "component_root"
  printf '%s\n' "$_COMPONENT_ROOT"  # out:return
  return 0
}

# Print the tag prefix of a component: nothing with one component (v1.2.3), "<name>/" with two or more (web/v1.2.3).
# Args:
#   $1 - name: Component name
# Returns: prefix (stdout), an empty line for the empty prefix
# Exits: 2 when no name is given, 4 on an unknown component
# Example: prefix="$(component_tag_prefix web)"
component_tag_prefix() {
  local name="${1:-}"
  [[ -n "$name" ]] || die_with "$BU_EXIT_USAGE" "component_tag_prefix: name required"
  _component_require_loaded "component_tag_prefix"

  local result
  result="$(json_query "$_COMPONENT_JSON" \
    'if any(.[]; .name == $n) | not then "E" elif length == 1 then "O" else "O" + $n + "/" end' --arg n "$name")"
  if [[ "${result:0:1}" == "E" ]]; then
    die_with "$BU_EXIT_NOT_FOUND" "component '${name}': not declared"
  fi
  printf '%s\n' "${result:1}"  # out:return
  return 0
}

# Print one field of a component. A list prints one entry per line, a field the component does not
# have prints nothing. Fields: name workspace paths version version_files checks split owner repo host.
# Args:
#   $1 - name: Component name
#   $2 - field: Field name
# Returns: the value (stdout)
# Exits: 2 on an unknown field, 4 on an unknown component
# Example: component_field web version
component_field() {
  local name="${1:-}" field="${2:-}"
  [[ -n "$name" && -n "$field" ]] || die_with "$BU_EXIT_USAGE" "component_field: name and field required"
  _component_require_loaded "component_field"

  if [[ " ${_COMPONENT_FIELDS} " != *" ${field} "* ]]; then
    die_with "$BU_EXIT_USAGE" "component_field: unknown field '${field}' (fields: ${_COMPONENT_FIELDS})"
  fi

  local found
  found="$(json_query "$_COMPONENT_JSON" 'any(.[]; .name == $n)' --arg n "$name")"
  if [[ "$found" != "true" ]]; then
    die_with "$BU_EXIT_NOT_FOUND" "component '${name}': not declared"
  fi

  json_query "$_COMPONENT_JSON" \
    '.[] | select(.name == $n) | .[$f] | if . == null then empty elif type == "array" then .[] else . end' \
    --arg n "$name" --arg f "$field"  # out:return
}

# Print the directories of a component relative to the repository root, one per line.
# paths: as written, "." for the whole repository. workspace: the directory of the package and of every
# workspace package it depends on, directly or through others, asked from pnpm on the host on every call
# and never stored; the package comes first.
# Args:
#   $1 - name: Component name
# Returns: directories (stdout)
# Exits: 3 when pnpm is missing or fails or the package is not in the workspace, 4 on an unknown component
# Example: component_paths web
component_paths() {
  local name="${1:-}"
  [[ -n "$name" ]] || die_with "$BU_EXIT_USAGE" "component_paths: name required"
  _component_require_loaded "component_paths"

  local out
  out="$(json_query "$_COMPONENT_JSON" \
    '.[] | select(.name == $n) | (.workspace // ""), .paths[]' --arg n "$name")"
  if [[ -z "$out" ]]; then
    die_with "$BU_EXIT_NOT_FOUND" "component '${name}': not declared"
  fi

  local -a lines
  readarray -t lines <<< "$out"
  local workspace="${lines[0]}"

  if [[ -z "$workspace" ]]; then
    printf '%s\n' "${lines[@]:1}"  # out:return
    return 0
  fi

  if ! command_exists pnpm; then
    die_with "$BU_EXIT_CONFIG" "component '${name}': workspace '${workspace}' needs pnpm on the host, install pnpm 10 (the tool image carries none)"
  fi

  local graph
  graph="$(cd "$_COMPONENT_ROOT" && pnpm list -r --depth -1 --json --filter "${workspace}...")" \
    || die_with "$BU_EXIT_CONFIG" "component '${name}': pnpm failed to list the workspace package '${workspace}'"

  local paths
  paths="$(json_query "$graph" \
    'if any(.[]; .name == $w) then (map(select(.name == $w)) + map(select(.name != $w)))[] | .path else empty end' \
    --arg w "$workspace")"
  if [[ -z "$paths" ]]; then
    die_with "$BU_EXIT_CONFIG" "component '${name}': workspace package '${workspace}' is not in the pnpm workspace"
  fi

  local abs rel
  while IFS= read -r abs; do
    if [[ "$abs" == "$_COMPONENT_ROOT" ]]; then
      rel="."
    elif [[ "$abs" == "$_COMPONENT_ROOT"/* ]]; then
      rel="${abs#"$_COMPONENT_ROOT"/}"
    else
      die_with "$BU_EXIT_CONFIG" "component '${name}': workspace directory ${abs} is outside the repository ${_COMPONENT_ROOT}"
    fi
    printf '%s\n' "$rel"  # out:return
  done <<< "$paths"
  return 0
}

return 0
