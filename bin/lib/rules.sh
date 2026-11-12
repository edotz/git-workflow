#!/bin/bash
# Branch Rulesets Library
# Requires: core.sh, yaml.sh, json.sh
# Provides: rules_load, rules_json, rules_names, rules_stages: the rulesets of the master, release and legacy branches as plain
#           GitHub ruleset JSON, built from bin/config/rulesets.yaml.
# State: sets RULES_DOC, the rulesets file as JSON, after rules_load.

# Guard against multiple sourcing
if [[ -n "${BU_STATE_RULES:-}" ]]; then return 0; fi
BU_STATE_RULES=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BU_LIB}/yaml.sh"
source "${BU_LIB}/json.sh"

# ============================================
# Rules Constants
# ============================================

readonly RULES_DEFAULT_STAGE="development"

RULES_DOC=""

# ============================================
# Private Helpers
# ============================================

# Stop unless rules_load has run.
# Args: none
_rules_require_loaded() {
  if [[ -z "$RULES_DOC" ]]; then
    die_with "$BU_EXIT_CONFIG" "rules: call rules_load before rules_json or rules_names"
  fi
  return 0
}

# ============================================
# Rules Functions
# ============================================

# Read the rulesets file into RULES_DOC and check its shape: a list of stages and a map of rulesets.
# Args: $1 - path of the rulesets file
# Sets: RULES_DOC
# Exits: 4 when the file is missing, 3 when it has no stages or rulesets
# Example: rules_load "${PLUGIN_ROOT}/bin/config/rulesets.yaml"
rules_load() {
  local file="${1:-}"
  [[ -n "$file" ]] || die_with "$BU_EXIT_USAGE" "rules_load: file required"
  require_file "$file" "rulesets file"

  local doc
  doc=$(yaml_to_json "$file")
  if ! json_validate "$doc"; then
    die_with "$BU_EXIT_CONFIG" "rules: ${file} is not valid YAML"
  fi
  if ! json_query "$doc" '(.stages | type == "array" and length > 0) and (.rulesets | type == "object" and length > 0)' -e >/dev/null; then
    die_with "$BU_EXIT_CONFIG" "rules: ${file} needs a stages list and a rulesets map"
  fi
  RULES_DOC="$doc"
  logger_debug "rules: loaded ${file}"
  return 0
}

# Print the names of the rulesets, one per line, in file order.
# Args: none
# Returns: names on stdout
# Example: rules_names
rules_names() {
  _rules_require_loaded
  json_query "$RULES_DOC" '.rulesets | keys_unsorted[]'
  return 0
}

# Print the names of the stages, one per line, in file order.
# Args: none
# Returns: names on stdout
# Example: rules_stages
rules_stages() {
  _rules_require_loaded
  json_query "$RULES_DOC" '.stages[]' -r
  return 0
}

# Print one ruleset as compact GitHub ruleset JSON for a stage.
# The stage is the second argument, else GIT_WORKFLOW_STAGE from the environment, else development; a stage the
# file does not list is refused. A ruleset with include_from takes its branch patterns from that environment
# setting, comma separated, else from its include_default, and a pattern without refs/ or ~ is read as a branch name.
# The bypass actor id stays APP_ID_PLACEHOLDER: rules-sync sets it.
# Args:
#   $1 - ruleset name (see rules_names)
#   $2 - stage, optional
# Returns: ruleset JSON on stdout
# Exits: 2 on an unknown name or stage, 3 when include_from names an empty setting and the ruleset has no include_default
# Example: rules_json master production
rules_json() {
  local name="${1:-}" stage="${2:-${GIT_WORKFLOW_STAGE:-$RULES_DEFAULT_STAGE}}"
  [[ -n "$name" ]] || die_with "$BU_EXIT_USAGE" "rules_json: name required"
  _rules_require_loaded

  if ! json_query "$RULES_DOC" '.rulesets | has($n)' -e --arg n "$name" >/dev/null; then
    die_with "$BU_EXIT_USAGE" "rules: unknown ruleset ${name}"
  fi
  if ! json_query "$RULES_DOC" '.stages | index($s)' -e --arg s "$stage" >/dev/null; then
    die_with "$BU_EXIT_USAGE" "rules: unknown stage ${stage}"
  fi

  local from default patterns=""
  from=$(json_query "$RULES_DOC" '.rulesets[$n].include_from // ""' --arg n "$name")
  if [[ -n "$from" ]]; then
    patterns="${!from:-}"
    if [[ -z "${patterns//[[:space:],]/}" ]]; then
      default=$(json_query "$RULES_DOC" '.rulesets[$n].include_default // ""' --arg n "$name")
      patterns="$default"
    fi
    if [[ -z "${patterns//[[:space:],]/}" ]]; then
      die_with "$BU_EXIT_CONFIG" "rules: ${name} needs ${from}, the comma separated branch patterns"
    fi
  fi

  json_query "$RULES_DOC" '
    .rulesets as $rs
    | $rs[$n] as $r
    | ($rs[$r.extends // $n] * ($r | del(.extends, .include_from, .include_default))) as $m
    | ($m.rules | if type == "object" then .[$s] else . end) as $rules
    | ($p | split(",") | map(gsub("^\\s+|\\s+$"; "") | select(length > 0))
        | map(if startswith("refs/") or startswith("~") then . else "refs/heads/" + . end)) as $inc
    | ($m.conditions.ref_name | if ($inc | length) > 0 then .include = $inc else . end) as $ref
    | {name: $n, target: $m.target, enforcement: $m.enforcement,
       conditions: {ref_name: $ref}, bypass_actors: $m.bypass_actors, rules: $rules}
  ' -c --arg n "$name" --arg s "$stage" --arg p "$patterns"
  return 0
}

return 0
