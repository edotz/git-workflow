#!/usr/bin/env bash
# Git Hook Shims
# Puts the shim of every git hook the plugin maps (adapters/git/hooks/hooks.yaml) into the directory git runs
# hooks from: core.hooksPath when set, else the common git dir of the repository, so a worktree shares it.
# The shims are the files of .git-templates/hooks/<git hook>; a mapped hook with no shim file is a problem.
# A file there without the agentic-os-hook marker is not ours: it is reported and left as it is.
# Usage: bash bin/app git shims [--check]
# Exit codes: 0 every shim is in place, 1 --check found a shim missing or stale or a write failed, 3 a conflict,
#             a mapped hook with no shim file or no hook mapped at all, 4 not inside a repository or the mapping
#             file is missing
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${BU_LIB}/files.sh"
source "${BU_LIB}/json.sh"
source "${BU_LIB}/yaml.sh"

cli_set_spec \
  name        "${MODULE_NAME:-shims}" \
  description "${MODULE_DESCRIPTION:-Put the git hook shims where git runs them.}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_flag "check" "c" "Report what is missing or stale and change nothing"

readonly SHIM_MARKER="agentic-os-hook"

main() {
  cli_parse "$@"
  cd "$PROJECT_ROOT"

  local hooks_dir mapping check="${CLI_FLAGS[check]:-}"
  hooks_dir=$(git_hooks_dir) || die_with "$BU_EXIT_NOT_FOUND" "shims: not inside a git repository"
  mapping="${PLUGIN_ROOT:?shims: PLUGIN_ROOT is not set}/adapters/git/hooks/hooks.yaml"
  require_file "$mapping" "git hook mapping"

  local event template target problems=0 stale=0 mapped=0
  while IFS= read -r event; do
    mapped=$((mapped + 1))
    template="${PLUGIN_ROOT}/.git-templates/hooks/${event}"
    target="${hooks_dir}/${event}"
    if [[ ! -f "$template" ]]; then
      print_line "${event}: no shim file ${template#"${PLUGIN_ROOT}"/}"
      problems=$((problems + 1))
    elif [[ -e "$target" ]] && ! grep -q "^# ${SHIM_MARKER}:" "$target"; then
      print_line "${event}: conflict, ${target} is not an agentic-os shim and stays as it is"
      problems=$((problems + 1))
    elif [[ -x "$target" ]] && cmp -s "$template" "$target"; then
      print_line "${event}: current"
    elif [[ -n "$check" ]]; then
      print_line "${event}: missing or stale in ${hooks_dir}"
      stale=$((stale + 1))
    else
      mkdir -p "$hooks_dir"
      copy_file_atomic "$template" "$target" || die_with "$BU_EXIT_FAILURE" "shims: could not write ${target}"
      print_line "${event}: installed in ${hooks_dir}"
    fi
  done < <(json_query "$(yaml_to_json "$mapping")" '.hooks[] | select(.targets != null) | .targets[0].event // empty' -r)

  if [[ "$mapped" -eq 0 ]]; then
    die_with "$BU_EXIT_CONFIG" "shims: no git hook is mapped in ${mapping}"
  fi
  if [[ "$problems" -gt 0 ]]; then
    die_with "$BU_EXIT_CONFIG" "shims: ${problems} hook(s) need attention"
  fi
  if [[ "$stale" -gt 0 ]]; then
    return "$BU_EXIT_FAILURE"
  fi
  return 0
}

main "$@"
