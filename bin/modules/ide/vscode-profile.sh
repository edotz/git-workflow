#!/bin/bash
# Compose and decompose VS Code .code-profile files.
# Decomposes a .code-profile into human-editable settings.json + extensions.json.
# Composes those files back into an importable .code-profile.
#
# Usage:
#   app ide vscode-profile decompose <file.code-profile> [--out <name>]
#   app ide vscode-profile compose --profile <name>
#   app ide vscode-profile list

set -euo pipefail

source "${BU_ROOT}/lib/core.sh"
source "${BU_LIB}/json.sh"
source "${BU_LIB}/cli.sh"

cli_set_spec \
  name        "ide vscode-profile" \
  description "Compose and decompose VS Code .code-profile files" \
  version     "1.0.0"

cli_add_option "profile" "p" "Profile name (required for compose)" ""
cli_add_option "out"     "o" "Override output directory name (decompose only)" ""

cli_register_subcommand "decompose" "cmd_decompose" "Extract settings + extensions from a .code-profile"
cli_register_subcommand "compose"   "cmd_compose"   "Build .code-profile from source files"
cli_register_subcommand "list"      "cmd_list"      "List all profiles with compose status"

# ============================================
# Locate the profiles directory
# ============================================

_resolve_profiles_root() {
  echo "${PLUGIN_EDOTZ_GIT_WORKFLOW_VSCODE_PROFILES_DIR:-${PLUGIN_ROOT}/ide/profiles}"  # out:return
}

# ============================================
# Business Logic
# ============================================

cmd_decompose() {
  local input_file="${CLI_ARGS[1]:-}"
  local out_name
  out_name=$(cli_get_option "out")
  local profiles_root
  profiles_root=$(_resolve_profiles_root)

  [[ -n "$input_file" ]] || die "vscode-profile decompose: file argument required"
  [[ -f "$input_file" ]] || die "vscode-profile decompose: file not found: $input_file"

  local raw
  raw="$(cat "$input_file")"
  json_validate "$raw" || die "vscode-profile decompose: invalid JSON in $input_file"

  local file_name
  file_name="$(json_get_with_default "$raw" "name" "")"

  local dir_name="${out_name:-${file_name,,}}"
  [[ -n "$dir_name" ]] || die "vscode-profile decompose: cannot determine profile name (use --out)"

  local out_dir="${profiles_root}/${dir_name}"
  mkdir -p "$out_dir"

  local settings_raw settings_json
  settings_raw="$(json_get_with_default "$raw" "settings" "")"

  if [[ -n "$settings_raw" ]] && [[ "$settings_raw" != "null" ]]; then
    settings_json="$(printf '%s' "$settings_raw" | jq -r '.settings' | jq '.' 2>/dev/null)" || \
      die "vscode-profile decompose: failed to parse settings field"
    printf '%s' "$settings_json" | jq_pretty_write "${out_dir}/settings.json"
    logger_success "settings → ${out_dir}/settings.json"
  else
    logger_warning "No settings field found in profile"
  fi

  local extensions_raw extensions_json
  extensions_raw="$(json_get_with_default "$raw" "extensions" "")"

  if [[ -n "$extensions_raw" ]] && [[ "$extensions_raw" != "null" ]]; then
    extensions_json="$(printf '%s' "$extensions_raw" | jq -r '.' 2>/dev/null)" || \
      die "vscode-profile decompose: failed to parse extensions field"
    printf '%s' "$extensions_json" | jq '[.[].identifier.id]' > "${out_dir}/extensions.json"
    local count
    count="$(json_length_file "${out_dir}/extensions.json")"
    logger_success "extensions ($count) → ${out_dir}/extensions.json"
  else
    logger_warning "No extensions field found in profile"
  fi

  logger_info "Profile decomposed to: ${out_dir}/"
}

cmd_compose() {
  local profile_name
  profile_name=$(cli_get_option "profile")
  local profiles_root
  profiles_root=$(_resolve_profiles_root)

  [[ -n "$profile_name" ]] || die "vscode-profile compose: --profile <name> required"

  local profile_dir="${profiles_root}/${profile_name}"
  [[ -d "$profile_dir" ]] || die "vscode-profile compose: profile directory not found: ${profile_dir}"

  local settings_file="${profile_dir}/settings.json"
  local extensions_file="${profile_dir}/extensions.json"

  [[ -f "$settings_file" ]]   || die "vscode-profile compose: missing ${settings_file}"
  [[ -f "$extensions_file" ]] || die "vscode-profile compose: missing ${extensions_file}"

  json_validate "$(cat "$settings_file")"   || die "vscode-profile compose: invalid JSON in settings.json"
  json_validate "$(cat "$extensions_file")" || die "vscode-profile compose: invalid JSON in extensions.json"

  local merged_settings merged_extensions
  if [[ "$profile_name" == "base" ]]; then
    merged_settings="$(cat "$settings_file")"
    merged_extensions="$(cat "$extensions_file")"
  else
    local base_settings_file="${profiles_root}/base/settings.json"
    local base_extensions_file="${profiles_root}/base/extensions.json"
    [[ -f "$base_settings_file" ]]   || die "vscode-profile compose: missing base/settings.json"
    [[ -f "$base_extensions_file" ]] || die "vscode-profile compose: missing base/extensions.json"
    merged_settings="$(jq -s '.[0] * .[1]' "$base_settings_file" "$settings_file")"
    merged_extensions="$(jq -s '(.[0] + .[1]) | unique | sort' "$base_extensions_file" "$extensions_file")"
    local count
    count="$(printf '%s' "$merged_extensions" | jq 'length')"
    logger_info "Extensions: base + ${profile_name} delta → ${count} total"
  fi

  local settings_compact settings_encoded
  settings_compact="$(json_compact "$merged_settings")"
  settings_encoded="$(jq -n --arg s "$settings_compact" '{"settings": $s}' | jq -Rs '.')"

  local ext_objects ext_compact ext_encoded
  ext_objects="$(printf '%s' "$merged_extensions" | jq '[.[] | {"identifier": {"id": .}, "displayName": ., "applicationScoped": false}]')"
  ext_compact="$(json_compact "$ext_objects")"
  ext_encoded="$(printf '%s' "$ext_compact" | jq -Rs '.')"

  local out_file="${profiles_root}/${profile_name}.code-profile"
  jq -n \
    --arg name "$profile_name" \
    --argjson settings "$settings_encoded" \
    --argjson extensions "$ext_encoded" \
    '{"name": $name, "settings": $settings, "extensions": $extensions}' \
    > "$out_file"

  logger_success "Composed: ${out_file}"
  echo "$out_file"  # out:return
}

cmd_list() {
  local profiles_root
  profiles_root=$(_resolve_profiles_root)

  if [[ ! -d "$profiles_root" ]]; then
    logger_info "No profiles directory found at: ${profiles_root}"
    return 0
  fi

  local found=0
  for profile_dir in "${profiles_root}"/*/; do
    [[ -d "$profile_dir" ]] || continue
    local name
    name="$(basename "$profile_dir")"
    local status="(no .code-profile)"
    if [[ -f "${profiles_root}/${name}.code-profile" ]]; then status="(.code-profile present)"; fi
    local has_settings="✗" has_ext="✗"
    if [[ -f "${profile_dir}/settings.json" ]]; then has_settings="✓"; fi
    if [[ -f "${profile_dir}/extensions.json" ]]; then has_ext="✓"; fi
    logger_info "  ${name}  settings:${has_settings}  extensions:${has_ext}  ${status}"
    found=$((found + 1))
  done

  if [[ $found -eq 0 ]]; then logger_info "No profiles found in ${profiles_root}"; fi
}

# ============================================
# Helper: pretty-print JSON to file
# ============================================

jq_pretty_write() {
  local target="${1:-}"
  [[ -n "$target" ]] || die "jq_pretty_write: target path required"
  jq '.' > "$target"
}

# ============================================
# Entry Point
# ============================================

main() {
  cli_parse "$@"
  cli_route_subcommand "${CLI_ARGS[0]:-}"
}

main "$@"
