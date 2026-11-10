#!/bin/bash
# Split Utility Library
# Requires: core.sh, component.sh, tool.sh, docker
# Provides: split_head: the head commit of the split of a component, made by splitsh-lite in the tool image with one
#           --prefix per path of the component (D64, D67).
# State: none; splitsh-lite adds the objects of the split and its cache to the git directory of the repository and
#        creates no ref.

# Guard against multiple sourcing
if [[ -n "${BU_STATE_SPLIT:-}" ]]; then return 0; fi
BU_STATE_SPLIT=1

# Load core library (handles bootstrap initialization)
source "${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh"
source "${BASH_SOURCE[0]%/*}/component.sh"
source "${BASH_SOURCE[0]%/*}/tool.sh"

# ============================================
# Split Functions
# ============================================

# Split a component out of the repository around the current directory and print the head of the split history.
# The paths come from component_paths, so the components must be loaded; every path is one --prefix. The component
# that covers the whole repository (path .) has nothing to split from and is refused.
# Args:
#   $1 - name: Component name
#   $2 - origin: Commit or branch to split, optional (default HEAD)
# Returns: the head commit, 40 hex digits (stdout)
# Exits: 1 when splitsh-lite fails or prints no commit, 2 when no name is given or the component covers the whole
#        repository, 4 on an unknown component
# Example: head="$(split_head web)"
split_head() {
  local name="${1:-}" origin="${2:-HEAD}"
  [[ -n "$name" ]] || die_with "$BU_EXIT_USAGE" "split_head: name required"

  local out path head
  out="$(component_paths "$name")"

  local -a args=()
  while IFS= read -r path; do
    if [[ "$path" == "." ]]; then
      die_with "$BU_EXIT_USAGE" "split_head: component '${name}' covers the whole repository, there is nothing to split from"
    fi
    args+=("-prefix=${path}")
  done <<< "$out"

  tool_image_ensure
  head="$(tool_run splitsh-lite "${args[@]}" "-origin=${origin}" </dev/null)" \
    || die "split_head: splitsh-lite failed for component '${name}'"
  if [[ ! "$head" =~ ^[0-9a-f]{40}$ ]]; then
    die "split_head: splitsh-lite printed no commit for component '${name}', the paths have no history at ${origin}"
  fi
  printf '%s\n' "$head"  # out:return
  return 0
}

return 0
