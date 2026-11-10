#!/usr/bin/env bash
# Git Split - show the split of a component into its child repository: the new head, the ancestry and the tree difference
# Usage: app git split [<component>] (--dry-run | --apply)
# Settings: GIT_WORKFLOW_MAIN_BRANCH (default: master), the branch of the child repository that is read
# Decisions: D64, D67 of the concept: the child URL is built here from owner, repo and host; the dry run reads the child
#            with the credential of the developer (gh auth token) and tells an absent ref (ls-remote exit 2) from a
#            failed read; the apply is built by T5.3 and is not available yet
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${PLUGIN_ROOT}/bin/lib/tool.sh"
source "${PLUGIN_ROOT}/bin/lib/component.sh"
source "${PLUGIN_ROOT}/bin/lib/split.sh"

cli_set_spec \
  name        "${MODULE_NAME:-split}" \
  description "${MODULE_DESCRIPTION:-Show the split of a component into its child repository.}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_flag "dry-run" "n" "Print the split head, the ancestry to the child head and the tree difference; change nothing"
cli_add_flag "apply"   "a" "Force-push the split head to the child repository (not built yet)"

_SPLIT_AUTH=(-c "credential.helper=" -c "credential.helper=!gh auth git-credential")

# ============================================
# Private Helpers
# ============================================

# Print the https URL of the child repository of a component, built from owner, repo and host.
# Args: $1 - component name
_split_child_url() {
  local name="$1" owner repo host
  owner="$(component_field "$name" owner)" || return 1
  repo="$(component_field "$name" repo)" || return 1
  host="$(component_field "$name" host)" || return 1
  printf 'https://%s/%s/%s.git\n' "$host" "$owner" "$repo"  # out:return
  return 0
}

# Compare the child head with the split head and print the ancestry: the same commit, a fast-forward, a diverged
# history, or an unrelated one that needs a baseline (D64). Both commits are in the local object database.
# Args: $1 - child head  $2 - split head
# Returns: 1 when git merge-base fails, 0 otherwise
_split_report_ancestry() {
  local child="$1" head="$2" rc=0
  if [[ "$child" == "$head" ]]; then
    print_item ok "ancestry" "the child is at the split head already: nothing to apply"
    return 0
  fi
  if tool_run git merge-base --is-ancestor "$child" "$head" </dev/null; then
    print_item info "ancestry" "the child head is an ancestor of the split head: a fast-forward"
    return 0
  fi
  tool_run git merge-base "$child" "$head" </dev/null >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) print_item warning "ancestry" "the histories diverged: the child head is not an ancestor of the split head" ;;
    1) print_item warning "ancestry" "the child is unrelated to the split: it needs a baseline, its old head is tagged legacy/pre-split before the apply" ;;
    *)
      print_item error "ancestry" "git merge-base answered with ${rc}"
      return 1
      ;;
  esac
  return 0
}

# Print the files that differ between the child tree and the split tree, one line per file with its status
# (A only in the split, D only in the child, M changed).
# Args: $1 - child head  $2 - split head
# Returns: 1 when git diff fails, 0 otherwise
_split_report_tree() {
  local child="$1" head="$2" diff line
  local -a lines
  if ! diff="$(tool_run git diff --name-status --no-renames "$child" "$head" </dev/null)"; then
    print_item error "tree difference" "git diff failed between the child head and the split head"
    return 1
  fi
  if [[ -z "$diff" ]]; then
    print_item info "tree difference" "none"
    return 0
  fi
  readarray -t lines <<< "$diff"
  print_item info "tree difference" "${#lines[@]} file(s)"
  for line in "${lines[@]}"; do
    print_line "  ${line}"
  done
  return 0
}

# Show the split of one component: the split head, then, when the child exists, its head, the ancestry and the tree
# difference. A component with split no is skipped.
# Args: $1 - component name  $2 - branch of the child repository
# Returns: 1 when the split or the read of the child fails, 0 otherwise. The caller runs it inside an if, where set -e
# is off, so every command substitution that can die ends the function with an explicit return.
_split_dry_run() {
  local name="$1" branch="$2" url head out child rc=0 flag
  flag="$(component_field "$name" split)" || return 1
  if [[ "$flag" != "yes" ]]; then
    print_item info "$name" "skipped: split is no"
    return 0
  fi
  url="$(_split_child_url "$name")" || return 1
  head="$(split_head "$name")" || return 1

  print_header "split ${name}"
  print_item info "child" "$url"
  print_item info "split head" "$head"

  out="$(tool_run git "${_SPLIT_AUTH[@]}" ls-remote --exit-code --heads "$url" "refs/heads/${branch}" </dev/null 2>/dev/null)" || rc=$?
  case "$rc" in
    0) ;;
    2)
      print_item info "child head" "${branch} is absent on the child: the apply creates it"
      return 0
      ;;
    *)
      print_item error "child head" "failed read of ${url}: ls-remote answered with ${rc}"
      return 1
      ;;
  esac
  child="${out%%[[:space:]]*}"
  if ! tool_run git "${_SPLIT_AUTH[@]}" fetch --quiet --no-write-fetch-head "$url" "refs/heads/${branch}" </dev/null; then
    print_item error "child head" "failed read of ${url}: the fetch of ${branch} failed"
    return 1
  fi
  print_item info "child head" "$child"
  _split_report_ancestry "$child" "$head" || return 1
  _split_report_tree "$child" "$head" || return 1
  return 0
}

# ============================================
# Main
# ============================================

main() {
  cli_parse "$@"

  local name dry="no" apply="no" branch failed=0
  name="$(cli_get_arg 0)"
  if cli_flag_is_set "dry-run"; then dry="yes"; fi
  if cli_flag_is_set "apply"; then apply="yes"; fi
  if [[ "$dry" == "$apply" ]]; then
    die_with "$BU_EXIT_USAGE" "split: give exactly one of --dry-run and --apply"
  fi
  if [[ "$apply" == "yes" ]]; then
    die_with "$BU_EXIT_USAGE" "split: --apply is not built yet, use --dry-run"
  fi
  branch="${GIT_WORKFLOW_MAIN_BRANCH:-master}"

  git_ensure_repo
  cd "$PROJECT_ROOT"
  tool_image_ensure
  component_load "${PROJECT_ROOT}/components.yaml"

  local -a names known
  readarray -t known < <(component_names)
  if [[ -n "$name" ]]; then
    if [[ " ${known[*]} " != *" ${name} "* ]]; then
      die_with "$BU_EXIT_NOT_FOUND" "split: component '${name}' is not declared in components.yaml"
    fi
    names=("$name")
  else
    names=("${known[@]}")
  fi

  if command_exists gh; then
    GH_TOKEN="$(gh auth token 2>/dev/null || true)"
  fi

  for name in "${names[@]}"; do
    if ! _split_dry_run "$name" "$branch"; then
      failed=$((failed + 1))
    fi
  done
  if [[ "$failed" -gt 0 ]]; then
    die "split: ${failed} component(s) failed, see the lines above"
  fi
  return 0
}

main "$@"
