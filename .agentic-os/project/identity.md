# Identity

How the project is worked on, from the conventions the reports cite and the developer confirmed.

## Conventions

- Commit messages are conventional commits, enforced by commitlint locally (commit-msg hook) and in CI (commitlint.config.mjs; bin/hooks/commit-msg/conventional; .github/workflows/_callable-status-checks.yml).
- Repositories allow merge commits only today (bin/modules/git/templates/branch-protection.sh); the concept moves master to squash merge in the production phase.
- Bash under `set -euo pipefail`; a change to bin/lib or bin/modules is done when shellcheck is clean (confirmed).
- Plugin settings carry the prefix `PLUGIN_EDOTZ_GIT_WORKFLOW_`; the branches and settings come from `.env.defaults` and `.env`; `.github/workflow.env` is a remnant of the old integration and is deleted (bin/config/env.defaults; confirmed).

## Boundaries

- Generated files are never edited by hand; changes go through the templates and workflow-setup (generated headers).
- Code moved as-is from the framework stays unchanged until the redesign replaces it (product.md).
