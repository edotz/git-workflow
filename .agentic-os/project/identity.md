# Identity

How the project is worked on, from the conventions the reports cite and the developer confirmed.

## Conventions

- Commit messages are conventional commits, enforced by commitlint locally (commit-msg hook) and in CI (commitlint.config.mjs; bin/hooks/commit-msg/conventional; .github/workflows/_callable-status-checks.yml).
- Repositories allow merge commits only today (bin/modules/git/templates/branch-protection.sh); the concept moves master to squash merge in the production phase.
- Bash under `set -euo pipefail`; a change to bin/lib or bin/modules is done when shellcheck is clean (confirmed).
- Plugin settings in bin/config/env.defaults carry the prefix `PLUGIN_EDOTZ_GIT_WORKFLOW_`; the branch settings `GIT_WORKFLOW_MAIN_BRANCH` and `GIT_WORKFLOW_RELEASE_BRANCH` come from the project-root `.env`, with `master` as the fallback in code (D49, applied by T4.14); the tool pins come from `.env.defaults` and `.env` of the plugin root; `.github/workflow.env` is deleted.

## Boundaries

- Generated files are never edited by hand; changes go through the templates and workflow-setup (generated headers).
- Code moved as-is from the framework stays unchanged until the redesign replaces it (product.md).
