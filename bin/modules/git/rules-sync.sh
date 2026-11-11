#!/usr/bin/env bash
# Git Rules Sync - apply the branch rulesets of bin/config/rulesets.yaml to the repository of the remote origin
# Usage: app git rules-sync [--dry-run | --apply] [--stage <stage>]
# Settings: GIT_WORKFLOW_STAGE (default: development), GIT_WORKFLOW_APP_ID (bypass actor, required for --apply),
#           GIT_WORKFLOW_RELEASE_BRANCH, GIT_WORKFLOW_LEGACY_BRANCHES, TOKEN_SERVICE_URL, TOKEN_SERVICE_PORT
# Decisions: D16, D31, D58 of the concept and the plan: a ruleset whose branch setting is unset is skipped, master
#            always applies, and a ruleset the file does not name is never touched or deleted; a ruleset or a classic
#            branch protection that still covers a managed branch is named in the output and left alone
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/json.sh"
source "${PLUGIN_LIB}/rules.sh"
source "${PLUGIN_LIB}/remote.sh"
source "${PLUGIN_LIB}/token.sh"
source "${PLUGIN_LIB}/tool.sh"

cli_set_spec \
  name        "${MODULE_NAME:-rules-sync}" \
  description "${MODULE_DESCRIPTION:-Create or update the branch rulesets of the repository as the App.}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_flag   "dry-run" "n" "Print per ruleset create, update, unchanged or skipped; change nothing (default)"
cli_add_flag   "apply"   "a" "Create or update the rulesets through the Rulesets API as the App"
cli_add_option "stage"   "s" "Stage of the rulesets (default: GIT_WORKFLOW_STAGE, else development)" ""

readonly RULES_SYNC_PLACEHOLDER="APP_ID_PLACEHOLDER"
readonly RULES_SYNC_PERMISSION="administration"

_RULES_SYNC_BODY=""
_RULES_SYNC_OUTCOME=""
_RULES_SYNC_BRANCHES=()
declare -A _RULES_SYNC_IDS=()

# ============================================
# Private Helpers
# ============================================

# Replace the bypass actor id placeholder of _RULES_SYNC_BODY by the number of the App: the API wants an integer.
# Args: $1 - App id, digits only
# Sets: _RULES_SYNC_BODY
_rules_sync_set_actor() {
  local app_id="$1"
  _RULES_SYNC_BODY="$(json_query "$_RULES_SYNC_BODY" '
    if .bypass_actors then
      .bypass_actors |= map(if .actor_id == $ph then .actor_id = ($id | tonumber) else . end)
    else . end
  ' -c --arg ph "$RULES_SYNC_PLACEHOLDER" --arg id "$app_id")"
  return 0
}

# Read the rulesets of the repository by name into _RULES_SYNC_IDS (name to id).
# Args: $1 - owner/name
# Sets: _RULES_SYNC_IDS
_rules_sync_read_ids() {
  local slug="$1" list id name
  _RULES_SYNC_IDS=()
  list="$(tool_run gh api "repos/${slug}/rulesets?per_page=100&includes_parents=false" </dev/null)" \
    || die "rules-sync: cannot read the rulesets of ${slug}"
  if ! json_validate "$list"; then
    die "rules-sync: the rulesets of ${slug} came back as no JSON"
  fi
  while IFS=$'\t' read -r id name; do
    if [[ -n "$name" ]]; then
      _RULES_SYNC_IDS["$name"]="$id"
    fi
  done < <(json_query "$list" '.[] | "\(.id)\t\(.name)"' -r)
  return 0
}

# Decide what a ruleset needs: create when the repository has none of that name, unchanged when the live ruleset
# holds the same name, target, enforcement, conditions, bypass actors and rules, update otherwise.
# Args: $1 - owner/name  $2 - ruleset name
# Uses: _RULES_SYNC_BODY, _RULES_SYNC_IDS, _RULES_SYNC_LOOSE (true leaves the bypass actors out of the comparison: the App id is unknown)
# Sets: _RULES_SYNC_OUTCOME (create, update or unchanged)
_rules_sync_outcome() {
  local slug="$1" name="$2" id existing
  id="${_RULES_SYNC_IDS[$name]:-}"
  if [[ -z "$id" ]]; then
    _RULES_SYNC_OUTCOME="create"
    return 0
  fi
  existing="$(tool_run gh api "repos/${slug}/rulesets/${id}" </dev/null)" \
    || die "rules-sync: cannot read the ruleset ${name} (${id}) of ${slug}"
  if json_query "$existing" '
    def shape: {name, target, enforcement, conditions, bypass_actors, rules}
      | if $loose then del(.bypass_actors) else . end;
    shape == ($want | shape)
  ' -e --argjson want "$_RULES_SYNC_BODY" --argjson loose "$_RULES_SYNC_LOOSE" >/dev/null; then
    _RULES_SYNC_OUTCOME="unchanged"
  else
    _RULES_SYNC_OUTCOME="update"
  fi
  return 0
}

# Tell whether a branch is matched by one of the ref_name patterns of a ruleset: ~ALL, ~DEFAULT_BRANCH (the main branch
# setting) or a refs/heads pattern.
# Args: $1 - branch  $2.. - patterns
# Returns: 0 on a match, 1 otherwise
_rules_sync_ref_matches() {
  local branch="$1" pattern
  shift
  for pattern in "$@"; do
    case "$pattern" in
      "~ALL") return 0 ;;
      "~DEFAULT_BRANCH")
        if [[ "$branch" == "${GIT_WORKFLOW_MAIN_BRANCH:-master}" ]]; then return 0; fi
        ;;
      *)
        # shellcheck disable=SC2053 # the ref_name patterns of a ruleset are globs on purpose
        if [[ "refs/heads/${branch}" == $pattern ]]; then return 0; fi
        ;;
    esac
  done
  return 1
}

# Name what still guards a managed branch without being managed here: an active ruleset whose name the file does not
# carry, and the classic branch protection. A classic read that fails for any reason but a 404 is a failed read, never
# "not protected". Prints only, nothing is deleted.
# Args: $1 - owner/name
# Uses: _RULES_SYNC_IDS (name to id, read before the run), _RULES_SYNC_BRANCHES (the branches of the managed rulesets)
_rules_sync_report_foreign() {
  local slug="$1" name id ruleset managed branch out rc checks known
  local -a include exclude managed_names
  mapfile -t managed_names < <(rules_names)
  for name in $(printf '%s\n' "${!_RULES_SYNC_IDS[@]}" | sort); do
    known="no"
    for managed in "${managed_names[@]}"; do
      if [[ "$managed" == "$name" ]]; then known="yes"; fi
    done
    if [[ "$known" == "yes" ]]; then continue; fi
    id="${_RULES_SYNC_IDS[$name]}"
    ruleset="$(tool_run gh api "repos/${slug}/rulesets/${id}" </dev/null)" \
      || die "rules-sync: cannot read the ruleset ${name} (${id}) of ${slug}"
    if [[ "$(json_query "$ruleset" '.enforcement' -r)" != "active" ]]; then continue; fi
    mapfile -t include < <(json_query "$ruleset" '.conditions.ref_name.include[]?' -r)
    mapfile -t exclude < <(json_query "$ruleset" '.conditions.ref_name.exclude[]?' -r)
    for branch in "${_RULES_SYNC_BRANCHES[@]}"; do
      if _rules_sync_ref_matches "$branch" "${include[@]}" && ! _rules_sync_ref_matches "$branch" "${exclude[@]}"; then
        print_item warning "foreign ruleset ${id} ${name} covers ${branch}"
      fi
    done
  done
  for branch in "${_RULES_SYNC_BRANCHES[@]}"; do
    rc=0
    out="$(tool_run gh api "repos/${slug}/branches/${branch}/protection" </dev/null 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      if json_validate "$out"; then
        checks="$(json_query "$out" '[.required_status_checks.contexts[]?] | join(", ")' -r)"
      else
        checks="unreadable"
      fi
      print_item warning "classic protection covers ${branch}" "required checks: ${checks:-none}"
    elif [[ "$out" != *"(HTTP 404)"* ]]; then
      print_item warning "classic protection of ${branch}" "failed read: ${out##*$'\n'}"
    fi
  done
  return 0
}

# Send _RULES_SYNC_BODY to the Rulesets API.
# Args: $1 - method (POST or PUT)  $2 - endpoint
_rules_sync_write() {
  local method="$1" endpoint="$2"
  tool_run gh api --method "$method" "$endpoint" --input - <<<"$_RULES_SYNC_BODY" >/dev/null \
    || die "rules-sync: ${method} ${endpoint} failed"
  return 0
}

# ============================================
# Main
# ============================================

main() {
  cli_parse "$@"

  local dry="no" apply="no" stage app_id
  if cli_flag_is_set "dry-run"; then dry="yes"; fi
  if cli_flag_is_set "apply"; then apply="yes"; fi
  if [[ "$dry" == "yes" && "$apply" == "yes" ]]; then
    die_with "$BU_EXIT_USAGE" "rules-sync: give at most one of --dry-run and --apply"
  fi
  stage="$(cli_get_option "stage")"
  stage="${stage:-${GIT_WORKFLOW_STAGE:-$RULES_DEFAULT_STAGE}}"
  app_id="${GIT_WORKFLOW_APP_ID:-}"

  if [[ "$apply" == "yes" ]]; then
    if [[ -z "$app_id" ]]; then
      die_with "$BU_EXIT_CONFIG" "rules-sync: --apply needs GIT_WORKFLOW_APP_ID, the id of the App, in the project-root .env"
    fi
    if [[ ! "$app_id" =~ ^[0-9]+$ ]]; then
      die_with "$BU_EXIT_CONFIG" "rules-sync: GIT_WORKFLOW_APP_ID must be the numeric id of the App"
    fi
  fi

  cd "$PROJECT_ROOT"
  local slug
  slug="$(remote_slug)"
  rules_load "${PLUGIN_ROOT}/bin/config/rulesets.yaml"

  local -a names=()
  mapfile -t names < <(rules_names)

  if [[ "$apply" == "yes" ]]; then
    token_fetch "$slug" "$RULES_SYNC_PERMISSION"
  elif command -v gh >/dev/null 2>&1; then
    # The dry run only reads: the developer login is enough and the token service is not asked.
    GH_TOKEN="$(gh auth token 2>/dev/null || true)"
  fi
  _rules_sync_read_ids "$slug"

  if [[ "$apply" == "yes" ]]; then
    print_header "rules-sync ${slug} (stage ${stage}, apply)"
  else
    print_header "rules-sync ${slug} (stage ${stage}, dry run)"
  fi

  local name built rc ref
  for name in "${names[@]}"; do
    rc=0
    built="$(rules_json "$name" "$stage" 2>&1)" || rc=$?
    if [[ "$rc" -eq "$BU_EXIT_CONFIG" ]]; then
      print_item warning "$name" "skipped, ${built#Error: }"
      continue
    fi
    if [[ "$rc" -ne 0 ]]; then
      die_with "$rc" "rules-sync: ${built#Error: }"
    fi

    _RULES_SYNC_BODY="$built"
    while IFS= read -r ref; do
      if [[ "$ref" == refs/heads/* && "$ref" != *'*'* && " ${_RULES_SYNC_BRANCHES[*]} " != *" ${ref#refs/heads/} "* ]]; then
        _RULES_SYNC_BRANCHES+=("${ref#refs/heads/}")
      fi
    done < <(json_query "$built" '.conditions.ref_name.include[]?' -r)
    _RULES_SYNC_LOOSE="true"
    if [[ "$app_id" =~ ^[0-9]+$ ]]; then
      _rules_sync_set_actor "$app_id"
      _RULES_SYNC_LOOSE="false"
    fi
    _rules_sync_outcome "$slug" "$name"

    if [[ "$apply" == "yes" ]]; then
      case "$_RULES_SYNC_OUTCOME" in
        create) _rules_sync_write POST "repos/${slug}/rulesets" ;;
        update) _rules_sync_write PUT "repos/${slug}/rulesets/${_RULES_SYNC_IDS[$name]}" ;;
        *) ;;
      esac
    fi
    print_item ok "$name" "$_RULES_SYNC_OUTCOME"
  done

  _rules_sync_report_foreign "$slug"

  token_drop
  return 0
}

main "$@"
