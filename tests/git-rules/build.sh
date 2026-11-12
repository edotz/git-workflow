#!/usr/bin/env bash
# Purpose: Build every ruleset of bin/config/rulesets.yaml for every stage and check the JSON with jq (json_query).
# Usage: bash tests/git-rules/build.sh
# Arguments: none; BU_LIB must be set (the framework shell sets it)
# Output: one line per check, ok or FAIL
# Exit codes: 0 all checks hold, 1 a check failed
set -euo pipefail

ROOT="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
source "${BU_LIB:?run through bash bin/app or set BU_LIB}/core.sh"
source "${ROOT}/bin/lib/rules.sh"

failures=0

# Fail the check unless the jq program is true for the JSON.
# Args: $1 - label  $2 - JSON  $3 - jq program
check() {
  if json_query "$2" "$3" -e >/dev/null; then
    print_line "ok   $1"
  else
    print_line "FAIL $1"
    failures=$((failures + 1))
  fi
  return 0
}

# Fail the check unless the command ends with the status 2.
# Args: $1 - label  $2.. - command
refused() {
  local label="$1" status=0
  shift
  ("$@") >/dev/null 2>&1 || status=$?
  if [[ "$status" -eq 2 ]]; then
    print_line "ok   $label"
  else
    print_line "FAIL $label (status ${status})"
    failures=$((failures + 1))
  fi
  return 0
}

rules_load "${ROOT}/bin/config/rulesets.yaml"
export GIT_WORKFLOW_RELEASE_BRANCH="2.x"
export GIT_WORKFLOW_LEGACY_BRANCHES="0.x, release/1.x"

names=$(rules_names)
if [[ "$names" == $'master\nrelease\nlegacy' ]]; then
  print_line "ok   names are master, release, legacy"
else
  print_line "FAIL names are master, release, legacy"
  failures=$((failures + 1))
fi

for stage in development production; do
  for name in $names; do
    json=$(rules_json "$name" "$stage")
    label="${name}/${stage}"
    check "${label}: shape" "$json" \
      '.name == "'"$name"'" and .target == "branch" and .enforcement == "active"
       and (.conditions.ref_name.include | length > 0) and (.rules | type == "array") and (.bypass_actors | type == "array")'
    case "$name" in
      master)
        check "${label}: App is the only bypass actor" "$json" \
          '.bypass_actors == [{"actor_id": "APP_ID_PLACEHOLDER", "actor_type": "Integration", "bypass_mode": "always"}]'
        if [[ "$stage" == "development" ]]; then
          check "${label}: no pull request, no required check" "$json" '.rules == []'
        else
          check "${label}: pull request, squash only" "$json" \
            '[.rules[] | select(.type == "pull_request")] | length == 1 and (.[0].parameters.allowed_merge_methods == ["squash"])'
          check "${label}: aggregate check named check" "$json" \
            '[.rules[] | select(.type == "required_status_checks")] | length == 1 and (.[0].parameters.required_status_checks == [{"context": "check"}])'
          check "${label}: linear history" "$json" '[.rules[].type] | index("required_linear_history") != null'
        fi
        ;;
      release | legacy)
        check "${label}: App is the only bypass actor" "$json" \
          '.bypass_actors == [{"actor_id": "APP_ID_PLACEHOLDER", "actor_type": "Integration", "bypass_mode": "always"}]'
        check "${label}: release rules" "$json" \
          '[.rules[].type] | sort == ["deletion", "non_fast_forward", "pull_request", "required_linear_history"]'
        ;;
    esac
  done
done

check "legacy: the patterns of the project" "$(rules_json legacy production)" \
  '.conditions.ref_name.include == ["refs/heads/0.x", "refs/heads/release/1.x"]'
check "release: the branch of the project" "$(rules_json release production)" \
  '.conditions.ref_name.include == ["refs/heads/2.x"]'

refused "unknown stage is refused" rules_json master staging
refused "unknown name is refused" rules_json nothing production
status=0
(GIT_WORKFLOW_STAGE=staging rules_json master >/dev/null 2>&1) || status=$?
if [[ "$status" -eq 2 ]]; then
  print_line "ok   unknown GIT_WORKFLOW_STAGE is refused"
else
  print_line "FAIL unknown GIT_WORKFLOW_STAGE is refused (status ${status})"
  failures=$((failures + 1))
fi
check "default stage is development" "$(unset GIT_WORKFLOW_STAGE; rules_json master)" '.rules == []'
check "stage from GIT_WORKFLOW_STAGE" "$(GIT_WORKFLOW_STAGE=production rules_json master)" '.rules | length == 3'
check "master follows GIT_WORKFLOW_MAIN_BRANCH" "$(GIT_WORKFLOW_MAIN_BRANCH=main rules_json master production)" '.conditions.ref_name.include == ["refs/heads/main"]'
check "master falls back to master when the main branch setting is unset" "$(unset GIT_WORKFLOW_MAIN_BRANCH; rules_json master production)" '.conditions.ref_name.include == ["refs/heads/master"]'

status=0
(unset GIT_WORKFLOW_LEGACY_BRANCHES; rules_json legacy production >/dev/null 2>&1) || status=$?
if [[ "$status" -eq 3 ]]; then
  print_line "ok   legacy without patterns is a config failure"
else
  print_line "FAIL legacy without patterns is a config failure (status ${status})"
  failures=$((failures + 1))
fi

status=0
(unset GIT_WORKFLOW_RELEASE_BRANCH; rules_json release production >/dev/null 2>&1) || status=$?
if [[ "$status" -eq 3 ]]; then
  print_line "ok   release without a branch is a config failure"
else
  print_line "FAIL release without a branch is a config failure (status ${status})"
  failures=$((failures + 1))
fi

status=0
(GIT_WORKFLOW_LEGACY_BRANCHES=" , ,," rules_json legacy production >/dev/null 2>&1) || status=$?
if [[ "$status" -eq 3 ]]; then
  print_line "ok   legacy with only blank patterns is a config failure"
else
  print_line "FAIL legacy with only blank patterns is a config failure (status ${status})"
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  die_with "$BU_EXIT_FAILURE" "${failures} rules check(s) failed"
fi
print_line "all rules checks passed"
exit 0
