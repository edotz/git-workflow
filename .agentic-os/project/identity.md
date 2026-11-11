# Identity

How the project is worked on, from the conventions the reports cite and the developer confirmed.

## Conventions

- Commit messages are conventional commits, enforced by commitlint locally (commit-msg hook) and in CI (commitlint.config.mjs; bin/hooks/commit-msg/conventional; .github/workflows/status-checks.yml).
- Repositories merge by squash only: the ruleset of `master` allows the squash merge method, requires the check `check` and linear history, and lets the GitHub App bypass it to release; the pull request title is linted because it becomes the squash commit (bin/config/rulesets.yaml; bin/modules/git/pr.sh).
- Bash under `set -euo pipefail`; a change to bin/lib or bin/modules is done when shellcheck is clean (confirmed).
- Plugin settings in bin/config/env.defaults carry the prefix `PLUGIN_EDOTZ_GIT_WORKFLOW_`; the branch settings `GIT_WORKFLOW_MAIN_BRANCH` and `GIT_WORKFLOW_RELEASE_BRANCH` come from the project-root `.env`, with `master` as the fallback in code (D49, applied by T4.14); the tool pins come from `.env.defaults` and `.env` of the plugin root; `.github/workflow.env` is deleted.
- The daily loop runs through `app git start`, `commit`, `pr` and `check`; a release, its promotion and the split to a child repository run on the developer machine through `release`, `promote` and `split` with a token of the GitHub App.

## Boundaries

- Generated files are never edited by hand.
- A pull request never carries a release: the release commit and its tag are made by the App through `app git release`.
