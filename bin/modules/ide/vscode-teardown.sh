#!/bin/bash
# VS Code worktree teardown
# Removes the Project Manager entry for a worktree.
#
# Args:
#   --path <worktree_path>   absolute path to the worktree being removed

set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/json.sh"

# ============================================
# Parse arguments
# ============================================

worktree_path=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --path) worktree_path="${2:-}"; shift 2 ;;
    *) die "vscode-teardown: unknown argument: ${1:-}" ;;
  esac
done

[[ -n "$worktree_path" ]] || die "vscode-teardown: --path required"

# ============================================
# Remove Project Manager entry
# ============================================

# Prefer vscode-server (WSL/remote) over native install
if [[ -d "${HOME}/.vscode-server/data/User/globalStorage/alefragnani.project-manager" ]]; then
  pm_file="${HOME}/.vscode-server/data/User/globalStorage/alefragnani.project-manager/projects.json"
else
  pm_file="${HOME}/.config/Code/User/globalStorage/alefragnani.project-manager/projects.json"
fi

if [[ ! -f "$pm_file" ]]; then
  logger_debug "Project Manager file not found — nothing to remove"
  exit 0
fi

if ! json_validate "$(cat "$pm_file")"; then
  logger_warning "Project Manager file is invalid JSON — skipping teardown"
  exit 0
fi

updated="$(jq --arg p "$worktree_path" '[.[] | select(.rootPath != $p)]' "$pm_file")"
echo "$updated" > "${pm_file}.tmp" && mv "${pm_file}.tmp" "$pm_file"

logger_success "Project Manager entry removed: ${worktree_path}"
