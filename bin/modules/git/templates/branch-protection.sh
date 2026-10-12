#!/bin/bash
# Branch Protection YAML Templates
# Heredoc templates for branch-protection.yaml generation.
# Source this file before calling generate_branch_protection().
#
# Variables used (set by generate_branch_protection before env_substitute_vars calls):
#   BP_REPO_OWNER, BP_REPO_NAME   — repo identity
#   BP_ADMIN_USER                  — GitHub admin username (from config.yaml github.admin_user)
#   BP_BRANCH                      — branch pattern name (scalar)
#   BP_ENFORCE_ADMINS              — true | false (scalar)
#   BP_BYPASS_LINE                 — full YAML line: '              users: [...]' (scalar, no newline)
#
# Note: BP_TMPL_MAIN_BRANCH_TOP / _BOTTOM are split so the module can
#       inject multi-line context + bypass lines between them.

# File header + repo settings block
BP_TMPL_HEADER=$(cat <<'EOF'
# GENERATED — do not edit manually. Source: bin/modules/git/templates/branch-protection.sh via workflow-setup
repositories:
  - owner: $BP_REPO_OWNER
    name: $BP_REPO_NAME
    repository:
      allow_auto_merge: true
      allow_update_branch: true
      delete_branch_on_merge: true
      allow_merge_commit: true
      allow_squash_merge: false
      allow_rebase_merge: false
    branches:
EOF
)
export BP_TMPL_HEADER

# Wildcard branch block — open, no checks
BP_TMPL_WILDCARD=$(cat <<'EOF'
      - pattern: "*"
        protection:
          required_status_checks: null
          required_pull_request_reviews: null
          enforce_admins: false
          required_linear_history: false
          allow_force_pushes: false
          allow_deletions: false
          required_conversation_resolution: false
          lock_branch: false
          restrictions: null
EOF
)
export BP_TMPL_WILDCARD

# Main branch block — top half (up to and including "contexts:")
BP_TMPL_MAIN_BRANCH_TOP=$(cat <<'EOF'
      - pattern: "$BP_BRANCH"
        protection:
          required_status_checks:
            strict: true
            contexts:
EOF
)
export BP_TMPL_MAIN_BRANCH_TOP

# Main branch block — bottom half (after context lines and bypass line)
BP_TMPL_MAIN_BRANCH_BOTTOM=$(cat <<'EOF'
          enforce_admins: $BP_ENFORCE_ADMINS
          required_linear_history: false
          allow_force_pushes: false
          allow_deletions: false
          required_conversation_resolution: false
          lock_branch: false
          restrictions:
            users: ["$BP_ADMIN_USER"]
            teams: []
EOF
)
export BP_TMPL_MAIN_BRANCH_BOTTOM

# Main branch block — reviews section header (between contexts and bypass line)
BP_TMPL_MAIN_BRANCH_REVIEWS=$(cat <<'EOF'
          required_pull_request_reviews:
            dismiss_stale_reviews: false
            require_code_owner_reviews: false
            required_approving_review_count: 0
            bypass_pull_request_allowances:
EOF
)
export BP_TMPL_MAIN_BRANCH_REVIEWS

# Release/legacy/package branch block — no status checks, bypass admin user
BP_TMPL_RELEASE_BRANCH=$(cat <<'EOF'
      - pattern: "$BP_BRANCH"
        protection:
          required_status_checks:
            strict: true
            contexts: []
          required_pull_request_reviews:
            dismiss_stale_reviews: false
            require_code_owner_reviews: false
            required_approving_review_count: 0
            bypass_pull_request_allowances:
              users: ["$BP_ADMIN_USER"]
          enforce_admins: false
          required_linear_history: false
          allow_force_pushes: false
          allow_deletions: false
          required_conversation_resolution: false
          lock_branch: false
          restrictions:
            users: ["$BP_ADMIN_USER"]
            teams: []
EOF
)
export BP_TMPL_RELEASE_BRANCH

# Backup + settings footer block
BP_TMPL_FOOTER=$(cat <<'EOF'

backup:
  enabled: true
  storage:
    global:
      path: var/.github
      enabled: true
  retention:
    keep_last: 10
    keep_days: 90
    auto_cleanup: true
  verify_backup_before_apply: true
  backup_in_dry_run: false

settings:
  dry_run: false
  verbose: true
  gh_host: "github.com"
EOF
)
export BP_TMPL_FOOTER
