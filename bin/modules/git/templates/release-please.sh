#!/bin/bash
# Release Please Config Templates
# Heredoc templates for release-please-config.json generation.
# Source this file before calling generate_release_please_config().
#
# Variables used (set by generator before env_substitute_vars calls):
#   RP_RELEASE_TYPE   — node | php | simple
#   RP_PACKAGE_NAME   — e.g. @edotz/my-pkg (node only; empty string for php/simple)

# Full release-please-config.json template (node — includes package-name)
RP_TMPL_CONFIG_NODE=$(cat <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "$RP_RELEASE_TYPE",
      "package-name": "$RP_PACKAGE_NAME",
      "changelog-path": "CHANGELOG.md",
      "bump-minor-pre-major": true,
      "bump-patch-for-minor-pre-major": false,
      "draft": false,
      "prerelease": false,
      "include-component-in-tag": false,
      "include-v-in-tag": true,
      "pull-request-title-pattern": "chore(release): v${version}",
      "pull-request-header": "🚀 This PR contains the next release.",
      "separate-pull-requests": false,
      "skip-github-release": false,
      "release-search-depth": 10,
      "commit-search-depth": 100
    }
  },
  "changelog-sections": [
    { "type": "feat", "section": "Features", "hidden": false },
    { "type": "fix", "section": "Bug Fixes", "hidden": false },
    { "type": "perf", "section": "Performance Improvements", "hidden": false },
    { "type": "revert", "section": "Reverts", "hidden": false },
    { "type": "docs", "section": "Documentation", "hidden": false },
    { "type": "style", "section": "Styles", "hidden": true },
    { "type": "chore", "section": "Miscellaneous Chores", "hidden": true },
    { "type": "refactor", "section": "Code Refactoring", "hidden": true },
    { "type": "test", "section": "Tests", "hidden": true },
    { "type": "build", "section": "Build System", "hidden": true },
    { "type": "ci", "section": "Continuous Integration", "hidden": true }
  ]
}
EOF
)
export RP_TMPL_CONFIG_NODE

# Full release-please-config.json template (php / simple — no package-name)
RP_TMPL_CONFIG_OTHER=$(cat <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "$RP_RELEASE_TYPE",
      "changelog-path": "CHANGELOG.md",
      "bump-minor-pre-major": true,
      "bump-patch-for-minor-pre-major": false,
      "draft": false,
      "prerelease": false,
      "include-component-in-tag": false,
      "include-v-in-tag": true,
      "pull-request-title-pattern": "chore(release): v${version}",
      "pull-request-header": "🚀 This PR contains the next release.",
      "separate-pull-requests": false,
      "skip-github-release": false,
      "release-search-depth": 10,
      "commit-search-depth": 100
    }
  },
  "changelog-sections": [
    { "type": "feat", "section": "Features", "hidden": false },
    { "type": "fix", "section": "Bug Fixes", "hidden": false },
    { "type": "perf", "section": "Performance Improvements", "hidden": false },
    { "type": "revert", "section": "Reverts", "hidden": false },
    { "type": "docs", "section": "Documentation", "hidden": false },
    { "type": "style", "section": "Styles", "hidden": true },
    { "type": "chore", "section": "Miscellaneous Chores", "hidden": true },
    { "type": "refactor", "section": "Code Refactoring", "hidden": true },
    { "type": "test", "section": "Tests", "hidden": true },
    { "type": "build", "section": "Build System", "hidden": true },
    { "type": "ci", "section": "Continuous Integration", "hidden": true }
  ]
}
EOF
)
export RP_TMPL_CONFIG_OTHER
