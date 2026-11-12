#!/usr/bin/env bash
# Git Commit - commit the paths named, or exactly the staged files without paths, with a conventional message the
#              provider drafts or --message gives
# Usage: app git commit [--message <text>] [--yes] [<paths>]
# Decisions: D18 (the provider drafts, the plugin calls no provider binary), D37 of the plan (no repository hooks: the
#            message is linted here)
set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/cli.sh"
source "${BU_LIB}/git.sh"
source "${BU_LIB}/provider.sh"
source "${PLUGIN_LIB}/tool.sh"
source "${PLUGIN_LIB}/remote.sh"

cli_set_spec \
  name        "${MODULE_NAME:-commit}" \
  description "${MODULE_DESCRIPTION:-Stage the paths named and commit them with a conventional message.}" \
  version     "${MODULE_VERSION:-1.0.0}"

cli_add_option "message" "m" "Commit message; without it the provider drafts one from the staged diff" ""
cli_add_flag   "yes"     ""  "Commit without the confirmation; only together with --message"

readonly COMMIT_DIFF_LIMIT=30000

# The index before the paths were staged, as a tree; the cleanup restores it unless the commit was made.
_COMMIT_TREE=""
_COMMIT_MSGFILE=""
_COMMIT_ID=()

# ============================================
# Private Helpers
# ============================================

# Leave the index as it was when the command ends without a commit, and remove the message file.
_commit_cleanup() {
  if [[ -n "$_COMMIT_TREE" ]]; then
    tool_run git read-tree "$_COMMIT_TREE" </dev/null || true
    _COMMIT_TREE=""
  fi
  if [[ -n "$_COMMIT_MSGFILE" ]]; then
    rm -f "$_COMMIT_MSGFILE"
    _COMMIT_MSGFILE=""
  fi
  return 0
}

# Set _COMMIT_ID to the git arguments that give the commit the identity of the developer and switch the hooks of the
# repository off. The tool image has no global git config.
_commit_identity() {
  local name email
  name="$(remote_identity name)"
  email="$(remote_identity email)"
  _COMMIT_ID=(-c "user.name=${name}" -c "user.email=${email}" -c core.hooksPath=/dev/null)
  return 0
}

# Print the message the provider drafts from the staged diff of the paths, or of the whole index without them.
# Args: -- and the paths, or nothing
# Returns: the message (stdout)
_commit_draft() {
  local diff prompt message
  diff="$(tool_run git diff --cached "$@" </dev/null)"
  diff="${diff:0:${COMMIT_DIFF_LIMIT}}"
  prompt="Write the commit message for the staged diff below, as one conventional commit: type(scope): subject, in the imperative, lower case, at most 72 characters, no trailing period. Add a body only when the subject does not carry the change. Print the message and nothing else."$'\n\n'"${diff}"
  # The empty model lets the adapter pick its small model; a missing model makes it forward the prompt as a flag.
  message="$(provider_run_prompt "$prompt" "")" || die "commit: the provider gave no message, give one with --message"
  echo "$message" # out:return
  return 0
}

# Ask the developer to confirm; the answer is read from stdin, so an end of input declines.
_commit_confirm() {
  local answer=""
  print_prompt "Commit with this message? [y/N] "
  IFS= read -r answer || true
  case "${answer,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# ============================================
# Main
# ============================================

main() {
  cli_parse "$@"

  local message given yes="no" eaten
  local -a paths=()
  message="$(cli_get_option "message")"
  given="$message"
  if cli_flag_is_set "yes"; then yes="yes"; fi
  # cli_parse takes the word after a flag it does not know for its value, so a path right after --yes lands here.
  eaten="$(cli_get_option "yes")"
  if [[ -n "$eaten" ]]; then
    yes="yes"
    paths+=("$eaten")
  fi
  paths+=("${CLI_ARGS[@]}")

  git_ensure_repo
  tool_image_ensure
  _commit_identity
  if [[ -z "$message" ]] && ! provider_available; then
    die_with "$BU_EXIT_USAGE" "commit: no provider is available to draft the message, give one with --message"
  fi

  register_cleanup _commit_cleanup
  _COMMIT_TREE="$(tool_run git write-tree </dev/null)"
  local -a only=()
  if [[ "${#paths[@]}" -gt 0 ]]; then
    only=(-- "${paths[@]}")
    tool_run git add -- "${paths[@]}" </dev/null
    if tool_run git diff --cached --quiet -- "${paths[@]}" </dev/null; then
      die "commit: nothing to commit in the paths named"
    fi
  elif tool_run git diff --cached --quiet </dev/null; then
    die "commit: nothing staged, stage files or name the paths to commit"
  fi

  if [[ -z "$message" ]]; then
    message="$(_commit_draft "${only[@]}")"
  fi
  message="${message#"${message%%[![:space:]]*}"}"
  message="${message%"${message##*[![:space:]]}"}"
  local fence='```'
  if [[ "$message" == "$fence"* ]]; then
    message="${message#*$'\n'}"
    message="${message%"$fence"}"
    message="${message%"${message##*[![:space:]]}"}"
  fi
  if [[ -z "$message" ]]; then
    die "commit: the message is empty, give one with --message"
  fi

  _COMMIT_MSGFILE="$(mktemp)"
  printf '%s\n' "$message" > "$_COMMIT_MSGFILE"
  print_header "commit message"
  print_line "$message"
  if ! bash "${PLUGIN_ROOT}/bin/modules/git/lint-commit.sh" "$_COMMIT_MSGFILE"; then
    die_with "$BU_EXIT_CONFIG" "commit: the message is refused by lint-commit, nothing was committed"
  fi

  if [[ "$yes" == "no" || -z "$given" ]]; then
    if ! _commit_confirm; then
      die "commit: not confirmed, nothing was committed"
    fi
  fi

  if ! tool_run git "${_COMMIT_ID[@]}" commit -q -m "$message" "${only[@]}" </dev/null; then
    die "commit: git refused the commit, the index was restored"
  fi
  _COMMIT_TREE=""
  print_item ok "commit" "$(tool_run git rev-parse --short HEAD </dev/null)"
  return 0
}

main "$@"
