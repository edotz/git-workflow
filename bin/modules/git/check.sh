#!/usr/bin/env bash
# Git Check - the minimum check of the components of components.yaml
# Usage: app git check [component]
# Prints one line per component, ok or failed, and exits non-zero when any component is red. Writes nothing and
# fetches no token.
# Decisions: D32 of the concept: the minimum check is the commit lint since the latest tag plus the declared checks
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${PLUGIN_ROOT}/bin/lib/component.sh"
source "${PLUGIN_ROOT}/bin/lib/check.sh"

cli_set_spec \
  name        "${MODULE_NAME:-check}" \
  description "${MODULE_DESCRIPTION:-Run the minimum check of one component or of every component.}" \
  version     "${MODULE_VERSION:-1.0.0}"

# ============================================
# Main
# ============================================

main() {
  cli_parse "$@"

  local wanted names name red=0
  wanted="$(cli_get_arg 0)"

  git_ensure_repo
  cd "$PROJECT_ROOT"

  component_load "${PROJECT_ROOT}/components.yaml"
  names="$(component_names)"

  local -a selected
  readarray -t selected <<< "$names"
  if [[ -n "$wanted" ]]; then
    local known=no
    for name in "${selected[@]}"; do
      if [[ "$name" == "$wanted" ]]; then known=yes; fi
    done
    if [[ "$known" == "no" ]]; then
      die_with "$BU_EXIT_NOT_FOUND" "check: component '${wanted}' is not declared in components.yaml"
    fi
    selected=("$wanted")
  fi

  for name in "${selected[@]}"; do
    if check_minimum "$name"; then
      print_line "${name}: ok"
    else
      print_line "${name}: failed"
      red=$((red + 1))
    fi
  done

  if [[ "$red" -gt 0 ]]; then
    die "check: ${red} component(s) red"
  fi
  return 0
}

main "$@"
