#!/usr/bin/env bash
# Git Split - show the split of a component into its child repository: the new head, the ancestry and the tree difference
# Usage: app git split [<component>] --dry-run
#        app git split <component> --apply [--confirm <owner/repo>]
# Settings: GIT_WORKFLOW_MAIN_BRANCH (default: master), the branch of the child repository that is read
# Decisions: D64, D67 of the concept: the child URL is built here from owner, repo and host; the dry run reads the child
#            with the credential of the developer (gh auth token) and tells an absent ref (ls-remote exit 2) from a
#            failed read; the apply pushes one child per run with the installation token, the children follow the
#            rules of the monorepo (D73: GIT_WORKFLOW_MAIN_BRANCH, no setting of their own) and a child with another
#            default branch is refused (D74); a child that is unrelated or diverged is baselined: its old head is
#            tagged legacy/pre-split and the branch is replaced with a lease, only with --confirm (D64)
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${PLUGIN_LIB}/tool.sh"
source "${PLUGIN_LIB}/component.sh"
source "${PLUGIN_LIB}/split.sh"
source "${PLUGIN_LIB}/token.sh"

cli_set_spec \
  name        "${MODULE_NAME:-split}" \
  description "${MODULE_DESCRIPTION:-Show the split of a component into its child repository.}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_flag "dry-run" "n" "Print the split head, the ancestry to the child head and the tree difference; change nothing"
cli_add_flag "apply"   "a" "Push the split head and the component tags to the child repository, one child per run"
cli_add_option "confirm" "c" "owner/repo of the child: needed to replace a child that does not descend from the split" ""

# No repository hooks: the shims of a clone call agentic-os, which the tool image lacks.
_SPLIT_AUTH=(-c "core.hooksPath=/dev/null" -c "credential.helper=" -c "credential.helper=!gh auth git-credential")

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

# Print the branch the HEAD of the child points at; nothing when the child has no HEAD symref (an empty repository).
# Args: $1 - child URL
# Returns: 1 when the read fails, 0 otherwise
_split_child_default() {
  local url="$1" out line
  out="$(tool_run git "${_SPLIT_AUTH[@]}" ls-remote --symref "$url" HEAD </dev/null 2>/dev/null)" || return 1
  while IFS= read -r line; do
    if [[ "$line" == "ref: refs/heads/"* ]]; then
      line="${line#ref: refs/heads/}"
      printf '%s\n' "${line%%[[:space:]]*}"  # out:return
      return 0
    fi
  done <<< "$out"
  return 0
}

# Push the split of one component to its child repository: the split head to the branch of the monorepo, then the tags
# <component>/vX.Y.Z as vX.Y.Z at the split of the commit each tag names. The child is read with the credential of the
# developer, the installation token is fetched once and only when something is pushed. A child that does not descend
# from the split (unrelated or diverged) is baselined: its old head is tagged legacy/pre-split and the branch is
# replaced with a lease on that head, only with --confirm <owner/repo> (D64). Called without an if, so set -e holds.
# A child tag is compared at its commit: an annotated tag is peeled, the line ending in ^{} wins over the tag object.
# A child tag at another commit is skipped with a warning that names both commits, never moved, and the rest is pushed (D83).
# Args: $1 - component name  $2 - branch  $3 - value of --confirm, empty when not given
_split_apply() {
  local name="$1" branch="$2" confirm="$3"
  local flag owner repo slug url head default out child="" rc=0 mode="create" prefix tags_out line tag cname target
  local -a refspecs=() lease=() local_tags=()
  local -A child_tags=()

  flag="$(component_field "$name" split)"
  if [[ "$flag" != "yes" ]]; then
    die_with "$BU_EXIT_USAGE" "split: the component ${name} has split no, it has no child repository"
  fi
  owner="$(component_field "$name" owner)"
  repo="$(component_field "$name" repo)"
  slug="${owner}/${repo}"
  if [[ -n "$confirm" && "$confirm" != "$slug" ]]; then
    die_with "$BU_EXIT_USAGE" "split: --confirm names ${confirm}, the child of ${name} is ${slug}"
  fi
  url="$(_split_child_url "$name")"
  head="$(split_head "$name")"
  print_header "split ${name} (apply)"
  print_item info "child" "$url"
  print_item info "split head" "$head"

  default="$(_split_child_default "$url")" || die "split: failed read of ${url}: ls-remote --symref failed"
  if [[ -n "$default" && "$default" != "$branch" ]]; then
    die_with "$BU_EXIT_CONFIG" "split: the default branch of ${slug} is ${default} but GIT_WORKFLOW_MAIN_BRANCH is ${branch}: the children follow the rules of the monorepo, nothing was pushed"
  fi

  out="$(tool_run git "${_SPLIT_AUTH[@]}" ls-remote --exit-code --heads "$url" "refs/heads/${branch}" </dev/null 2>/dev/null)" || rc=$?
  case "$rc" in
    0)
      child="${out%%[[:space:]]*}"
      if ! tool_run git "${_SPLIT_AUTH[@]}" fetch --quiet --no-write-fetch-head "$url" "refs/heads/${branch}" </dev/null; then
        die "split: failed read of ${url}: the fetch of ${branch} failed"
      fi
      ;;
    2) ;;
    *) die "split: failed read of ${url}: ls-remote answered with ${rc}" ;;
  esac

  if [[ -n "$child" ]]; then
    rc=0
    if [[ "$child" == "$head" ]]; then
      mode="same"
    else
      tool_run git merge-base --is-ancestor "$child" "$head" </dev/null || rc=$?
      case "$rc" in
        0) mode="ff" ;;
        1) mode="baseline" ;;
        *) die "split: git merge-base answered with ${rc} for the child head ${child}" ;;
      esac
    fi
  fi
  if [[ "$mode" == "baseline" && -z "$confirm" ]]; then
    die_with "$BU_EXIT_USAGE" "split: ${slug} does not descend from the split: its old head ${child} would be kept as legacy/pre-split and ${branch} replaced; run the dry run, then again with --confirm ${slug}"
  fi

  prefix="$(component_tag_prefix "$name")"
  out="$(tool_run git "${_SPLIT_AUTH[@]}" ls-remote --tags "$url" </dev/null)" || die "split: failed read of ${url}: ls-remote --tags failed"
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      cname="${line#*refs/tags/}"
      child_tags["${cname%'^{}'}"]="${line%%[[:space:]]*}"
    fi
  done <<< "$out"
  tags_out="$(tool_run git tag --list "${prefix}v[0-9]*" </dev/null)"
  if [[ -n "$tags_out" ]]; then
    readarray -t local_tags <<< "$tags_out"
  fi
  for tag in "${local_tags[@]}"; do
    cname="${tag#"$prefix"}"
    split_head "$name" "$tag" >/dev/null
    target="$SPLIT_HEAD"
    if [[ -n "${child_tags[$cname]:-}" ]]; then
      if [[ "${child_tags[$cname]}" != "$target" ]]; then
        print_item warning "tag ${cname}" "skipped: ${slug} has it at ${child_tags[$cname]}, the split of ${tag} is ${target}: it is not moved"
      fi
      continue
    fi
    refspecs+=("${target}:refs/tags/${cname}")
  done

  if [[ "$mode" == "same" && "${#refspecs[@]}" -eq 0 ]]; then
    print_item ok "split" "${slug} is at the split head and lacks no tag that can be pushed: nothing to apply"
    return 0
  fi

  token_fetch "$slug" contents
  if [[ "$mode" == "baseline" ]]; then
    if ! tool_run git "${_SPLIT_AUTH[@]}" push "$url" "${child}:refs/tags/legacy/pre-split" </dev/null; then
      die "split: the tag legacy/pre-split of ${slug} could not be pushed, it may exist at another commit: delete or rename it on the child, then run again"
    fi
    print_item ok "legacy/pre-split" "the old head ${child} of ${slug} is kept"
    lease=("--force-with-lease=refs/heads/${branch}:${child}")
  fi
  if [[ "$mode" != "same" ]]; then
    refspecs=("${head}:refs/heads/${branch}" "${refspecs[@]}")
  fi
  tool_run git "${_SPLIT_AUTH[@]}" push --atomic "${lease[@]}" "$url" "${refspecs[@]}" </dev/null
  print_item ok "split" "${slug} ${branch} is at ${head}, ${#refspecs[@]} ref(s) pushed"
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

  local name dry="no" apply="no" branch failed=0 confirm
  name="$(cli_get_arg 0)"
  if cli_flag_is_set "dry-run"; then dry="yes"; fi
  if cli_flag_is_set "apply"; then apply="yes"; fi
  if [[ "$dry" == "$apply" ]]; then
    die_with "$BU_EXIT_USAGE" "split: give exactly one of --dry-run and --apply"
  fi
  confirm="$(cli_get_option "confirm")"
  if [[ "$apply" == "yes" && -z "$name" ]]; then
    die_with "$BU_EXIT_USAGE" "split: --apply takes the name of one component, one child per run"
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

  if [[ "$apply" == "yes" ]]; then
    _split_apply "$name" "$branch" "$confirm"
    token_drop
    return 0
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
