#!/usr/bin/env bash
# Git Stage - the stage of the live master ruleset, reported or switched
# Usage: app git stage [<stage>] [--apply]
# Settings: GIT_WORKFLOW_APP_ID (bypass actor, required for --apply), TOKEN_SERVICE_URL, TOKEN_SERVICE_PORT
# Decisions: the live ruleset is the source of truth of the stage; no setting stores it. The switch is rules-sync --apply
#            with the stage, and the ruleset is read again afterwards.
# Output: "live stage: <stage|drift|none>", a warning for each other ruleset that is missing or differs from
#         rulesets.yaml, then for a stage "unchanged", "would switch" or "switched"
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/json.sh"
source "${PLUGIN_LIB}/rules.sh"
source "${PLUGIN_LIB}/remote.sh"
source "${PLUGIN_LIB}/tool.sh"

cli_set_spec \
  name        "${MODULE_NAME:-stage}" \
  description "${MODULE_DESCRIPTION:-Report the stage of the live master ruleset, or switch it.}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_flag "apply" "a" "Switch the master ruleset to the stage as the App"

readonly STAGE_RULESET="master"

_STAGE_LIVE=""
_STAGE_LIST=""

# ============================================
# Private Helpers
# ============================================

# Read the live master ruleset and name its stage: the stage whose ruleset it holds in name, target, enforcement,
# conditions and rules, drift when it holds none of them, none when the repository has no master ruleset. The parameters
# GitHub adds to a rule by default do not count, and the bypass actors stay out of the comparison: they do not depend on
# the stage.
# Args: $1 - owner/name
# Sets: _STAGE_LIVE
_stage_read_live() {
  local slug="$1" list id existing stage built
  list="$(tool_run gh api "repos/${slug}/rulesets?per_page=100&includes_parents=false" </dev/null)" \
    || die "stage: cannot read the rulesets of ${slug}"
  if ! json_validate "$list"; then
    die "stage: the rulesets of ${slug} came back as no JSON"
  fi
  _STAGE_LIST="$list"
  id="$(json_query "$list" '[.[] | select(.name == $n)][0].id // empty' -r --arg n "$STAGE_RULESET")"
  if [[ -z "$id" ]]; then
    _STAGE_LIVE="none"
    return 0
  fi
  existing="$(tool_run gh api "repos/${slug}/rulesets/${id}" </dev/null)" \
    || die "stage: cannot read the ruleset ${STAGE_RULESET} (${id}) of ${slug}"

  _STAGE_LIVE="drift"
  while IFS= read -r stage; do
    built="$(rules_json "$STAGE_RULESET" "$stage")"
    if rules_live_matches "$existing" "$built" true; then
      _STAGE_LIVE="$stage"
      break
    fi
  done < <(rules_stages)
  return 0
}

# Warn for each ruleset besides master that is missing or differs from bin/config/rulesets.yaml. The stage does not
# change them, so the switch leaves them as they are; rules-sync aligns them. A ruleset whose branch setting is blank is
# left out, as rules-sync leaves it out.
# Args: $1 - owner/name
_stage_warn_others() {
  local slug="$1" name built rc id existing
  while IFS= read -r name; do
    if [[ "$name" == "$STAGE_RULESET" ]]; then continue; fi
    rc=0
    built="$(rules_json "$name" 2>&1)" || rc=$?
    if [[ "$rc" -eq "$BU_EXIT_CONFIG" ]]; then continue; fi
    if [[ "$rc" -ne 0 ]]; then
      die_with "$rc" "stage: ${built#Error: }"
    fi
    id="$(json_query "$_STAGE_LIST" '[.[] | select(.name == $n)][0].id // empty' -r --arg n "$name")"
    if [[ -z "$id" ]]; then
      print_item warning "$name" "missing, rules-sync --apply creates it"
      continue
    fi
    existing="$(tool_run gh api "repos/${slug}/rulesets/${id}" </dev/null)" \
      || die "stage: cannot read the ruleset ${name} (${id}) of ${slug}"
    if ! rules_live_matches "$existing" "$built" true; then
      print_item warning "$name" "differs from rulesets.yaml, rules-sync --apply aligns it"
    fi
  done < <(rules_names)
  return 0
}

# Tell whether a name is one of the stages.
# Args: $1 - name
_stage_is_known() {
  local known
  while IFS= read -r known; do
    if [[ "$known" == "$1" ]]; then return 0; fi
  done < <(rules_stages)
  return 1
}

# ============================================
# Main
# ============================================

main() {
  cli_parse "$@"

  local stage apply="no" before eaten rc=0
  stage="$(cli_get_arg 0 "")"
  if cli_flag_is_set "apply"; then apply="yes"; fi
  # cli_parse takes the word after a flag for its value, so a stage right after --apply lands here.
  eaten="$(cli_get_option "apply")"
  if [[ -n "$eaten" ]]; then
    apply="yes"
    stage="${stage:-$eaten}"
  fi
  if [[ "$apply" == "yes" && -z "$stage" ]]; then
    die_with "$BU_EXIT_USAGE" "stage: --apply needs the stage to switch to. Usage: app git stage [<stage>] [--apply]"
  fi

  cd "$PROJECT_ROOT"
  rules_load "${PLUGIN_ROOT}/bin/config/rulesets.yaml"
  if [[ -n "$stage" ]] && ! _stage_is_known "$stage"; then
    die_with "$BU_EXIT_USAGE" "stage: unknown stage ${stage}, one of $(rules_stages | tr '\n' ' ')"
  fi

  local slug
  slug="$(remote_slug)"
  if command -v gh >/dev/null 2>&1; then
    # The report only reads: the developer login is enough and the token service is not asked.
    GH_TOKEN="$(gh auth token 2>/dev/null || true)"
  fi
  _stage_read_live "$slug"
  before="$_STAGE_LIVE"

  print_header "stage ${slug}"
  print_line "live stage: ${before}"
  _stage_warn_others "$slug"
  if [[ -z "$stage" ]]; then
    return 0
  fi
  if [[ "$before" == "$stage" ]]; then
    print_line "unchanged: already ${stage}"
    return 0
  fi
  if [[ "$apply" == "no" ]]; then
    print_line "would switch: ${before} -> ${stage}"
    return 0
  fi

  bash "${PLUGIN_ROOT}/bin/modules/git/rules-sync.sh" --apply --stage "$stage" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    die_with "$rc" "stage: rules-sync failed, the live stage may be unchanged"
  fi
  _stage_read_live "$slug"
  if [[ "$_STAGE_LIVE" != "$stage" ]]; then
    die "stage: the live ruleset is ${_STAGE_LIVE} after the switch, not ${stage}"
  fi
  print_line "switched: ${before} -> ${stage}"
  return 0
}

main "$@"
