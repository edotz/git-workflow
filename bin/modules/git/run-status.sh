#!/usr/bin/env bash
# Git Run Status - Fetch recent GitHub Actions workflow runs
# Output: JSON array of recent runs for a repo/workflow

set -euo pipefail

# ============================================
# Load Libraries
# ============================================
source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/json.sh"
source "${PLUGIN_ROOT}/bin/lib/github.sh"
source "${BU_LIB}/cli.sh"

# ============================================
# CLI Specification
# ============================================
cli_set_spec \
  name        "${MODULE_NAME:-run-status}" \
  description "${MODULE_DESCRIPTION:-}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_option "repo"     "r" "Repository in owner/name format" ""
cli_add_option "workflow" "w" "Workflow name to filter"         ""
cli_add_option "limit"    "l" "Number of runs to return"        "5"

# ============================================
# Main
# ============================================
main() {
  cli_parse "$@"

  local repo workflow limit
  repo=$(cli_get_option "repo" "")
  workflow=$(cli_get_option "workflow" "")
  limit=$(cli_get_option "limit" "5")

  github_get_runs "$repo" "$workflow" "$limit"
}

main "$@"
