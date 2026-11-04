#!/usr/bin/env bash
# Node Linter
# Validates JavaScript files (*.js, *.mjs, *.cjs) with Biome, run from node_modules of the plugin root (decision D31)
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/lint.sh"

cli_set_spec \
  name        "${MODULE_NAME:-node}" \
  description "${MODULE_DESCRIPTION:-Lint Node files with Biome}" \
  version     "${MODULE_VERSION:-1.0.0}"

# Run Biome over the files with the biome.json of the plugin root.
# Args: $@ - files to lint
# Returns: 0 if passed, 1 if failed or Biome is not installed
lint_run_biome() {
  local biome="${PLUGIN_ROOT}/node_modules/.bin/biome"
  if [[ ! -x "$biome" ]]; then
    logger_error "biome is not installed: run npm ci in ${PLUGIN_ROOT}"
    return 1
  fi
  "$biome" lint --config-path="$PLUGIN_ROOT" "$@" 2>&1
}

# The mode full of lint_get_files lists shell scripts only, so the Node files are found here and handed to the
# generic flow as a specific list, without the hidden directories (.git, .claude, .agentic-os).
main() {
  local mode="${1:-staged}" found
  if [[ "$mode" == "full" ]]; then
    found="$(cd "$PROJECT_ROOT" && find . -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \) \
      ! -path "*/node_modules/*" ! -path "./.*/*" 2>/dev/null || true)"
    found="${found//$'\n'.\//$'\n'}"
    found="${found#./}"
    if [[ -z "$found" ]]; then
      print_line "No Node files to lint"
      return 0
    fi
    local -a list
    mapfile -t list <<< "$found"
    set -- specific "${list[@]}"
  fi
  lint_run_generic \
    "lint_run_biome" \
    "js|mjs|cjs" \
    "node" \
    "install Node" \
    "Node files" \
    "$@"
}

main "$@"
