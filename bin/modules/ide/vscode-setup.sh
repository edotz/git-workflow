#!/bin/bash
# VS Code worktree setup
# Writes .vscode/settings.json (title bar color), adds a Project Manager entry,
# and opens VS Code with the configured profile's --extensions-dir.
#
# Args:
#   --path    <worktree_path>   absolute path to the worktree
#   --type    <branch_type>     feat|bugfix|hotfix|chore|release
#   --name    <branch_name>     branch slug (optional, defaults to dirname)
#   --repo    <repo_name>       repository name (for PM tags)
#   --profile <profile_name>    VS Code profile key from vscode-profiles.json (optional)
#   --config  <worktree_json>   path to .worktree.json (optional)

set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/json.sh"

# ============================================
# Parse arguments
# ============================================

worktree_path=""
branch_type=""
branch_name=""
repo_name=""
profile_name=""
worktree_json=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --path)    worktree_path="${2:-}";  shift 2 ;;
    --type)    branch_type="${2:-}";    shift 2 ;;
    --name)    branch_name="${2:-}";    shift 2 ;;
    --repo)    repo_name="${2:-}";      shift 2 ;;
    --profile) profile_name="${2:-}";   shift 2 ;;
    --config)  worktree_json="${2:-}";  shift 2 ;;
    *) die "vscode-setup: unknown argument: ${1:-}" ;;
  esac
done

[[ -n "$worktree_path" ]] || die "vscode-setup: --path required"
[[ -n "$branch_type"   ]] || die "vscode-setup: --type required"
[[ -n "$repo_name"     ]] || die "vscode-setup: --repo required"

[[ -n "$branch_name" ]] || branch_name="$(basename "$worktree_path")"

# ============================================
# Load vscode config from .worktree.json
# ============================================

vscode_open="false"
vscode_title_bar="true"
color=""

if [[ -n "$worktree_json" ]] && [[ -f "$worktree_json" ]]; then
  vscode_open="$(json_get_file_with_default "$worktree_json" "vscode.open" "false")"
  vscode_title_bar="$(json_get_file_with_default "$worktree_json" "vscode.titleBar" "true")"
  color="$(json_get_file_with_default "$worktree_json" "vscode.colors.${branch_type}" "")"
  [[ -n "$profile_name" ]] || profile_name="$(json_get_file_with_default "$worktree_json" "vscode.profile" "")"
fi

# Default colors if not configured
if [[ -z "$color" ]]; then
  case "$branch_type" in
    feat)    color="#1e415e" ;;
    bugfix)  color="#a20000" ;;
    hotfix)  color="#a20000" ;;
    chore)   color="#2d5a27" ;;
    release) color="#6b3fa0" ;;
    *)       color="#333333" ;;
  esac
fi

# ============================================
# Write .vscode/settings.json (title bar color)
# ============================================

if [[ "$vscode_title_bar" == "true" ]]; then
  vscode_dir="${worktree_path}/.vscode"
  vscode_settings="${vscode_dir}/settings.json"

  mkdir -p "$vscode_dir"

  cat > "$vscode_settings" <<EOF
{
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "${color}",
    "titleBar.activeForeground": "#ffffff",
    "titleBar.inactiveBackground": "${color}cc"
  }
}
EOF

  logger_info "VS Code title bar color set: ${color} (${branch_type})"
fi

# ============================================
# Add Project Manager entry
# ============================================

# Prefer vscode-server (WSL/remote) over native install
if [[ -d "${HOME}/.vscode-server/data/User/globalStorage/alefragnani.project-manager" ]]; then
  pm_dir="${HOME}/.vscode-server/data/User/globalStorage/alefragnani.project-manager"
else
  pm_dir="${HOME}/.config/Code/User/globalStorage/alefragnani.project-manager"
fi
pm_file="${pm_dir}/projects.json"

mkdir -p "$pm_dir"

tag_type="${branch_type^}"

new_entry="$(jq -n \
  --arg name "${repo_name} (${branch_type}/${branch_name})" \
  --arg path "$worktree_path" \
  --arg tag1 "Worktree" \
  --arg tag2 "$tag_type" \
  --arg tag3 "$repo_name" \
  '{"name": $name, "rootPath": $path, "tags": [$tag1, $tag2, $tag3], "enabled": true}')"

if [[ -f "$pm_file" ]] && json_validate "$(cat "$pm_file")"; then
  updated="$(jq --arg p "$worktree_path" '[.[] | select(.rootPath != $p)]' "$pm_file")"
  echo "$updated" | jq ". += [$new_entry]" > "${pm_file}.tmp" && mv "${pm_file}.tmp" "$pm_file"
else
  echo "[$new_entry]" > "$pm_file"
fi

logger_success "Project Manager entry added: ${worktree_path}"

# ============================================
# Open VS Code
# ============================================

if [[ "$vscode_open" == "true" ]] && command_exists "code"; then
  if [[ -n "$profile_name" ]]; then
    logger_info "Opening VS Code with profile '${profile_name}': ${worktree_path}"
    code --profile "$profile_name" "$worktree_path" &
  else
    logger_info "Opening VS Code: ${worktree_path}"
    code "$worktree_path" &
  fi
fi
