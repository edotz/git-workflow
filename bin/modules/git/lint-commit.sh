#!/usr/bin/env bash
# Git Lint Commit - validate a commit message against the conventional commit config of the plugin
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/output.sh"
source "${BU_LIB}/json.sh"

main() {
  local msg_file="${1:-}"
  if [[ "$msg_file" == "--help" || "$msg_file" == "-h" ]]; then
    print_line "Usage: app git lint-commit <commit-msg-file> | --rules"
    return 0
  fi
  if [[ -z "$msg_file" ]]; then die_with "$BU_EXIT_USAGE" "Usage: app git lint-commit <commit-msg-file> | --rules"; fi

  local commitlint="${PLUGIN_ROOT}/node_modules/.bin/commitlint"
  if [[ ! -x "$commitlint" ]]; then die "commitlint is not installed: run npm install in ${PLUGIN_ROOT}"; fi

  if [[ "$msg_file" == "--rules" ]]; then
    local config
    config="$(NODE_PATH="${PLUGIN_ROOT}/node_modules" "$commitlint" --config "${PLUGIN_ROOT}/commitlint.config.mjs" --print-config json)"
    print_line "types: $(json_query "$config" '.rules["type-enum"][2] | join(" ")')"
    print_line "header: type(scope): subject, at most $(json_query "$config" '.rules["header-max-length"][2]') characters"
    return 0
  fi
  if [[ ! -f "$msg_file" ]]; then die "File not found: ${msg_file}"; fi

  NODE_PATH="${PLUGIN_ROOT}/node_modules" exec "$commitlint" --config "${PLUGIN_ROOT}/commitlint.config.mjs" --edit "$msg_file"
}

main "$@"
