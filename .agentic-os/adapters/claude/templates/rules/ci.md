---
paths:
  - ".github/workflows/**"
---

# GitHub Actions workflows

GitHub Actions workflows: status-checks.yml, the one pull-request check with the job check (commit lint, pull request title lint and the checks of components.yaml); release, promote and split run on the developer machine, not here.

## Purpose and conventions
- .github/workflows holds status-checks.yml only; it runs on every pull request (opened, edited, synchronize, reopened) with read permissions, in one job named `check` (status-checks.yml).
- The job lints the commits of the pull request with `wagoid/commitlint-github-action@v6` and `commitlint.config.mjs`, lints the pull request title with the same rules because the title becomes the squash commit, and runs every command that a component of components.yaml lists under `checks` (status-checks.yml).
- The same minimum check runs locally through `app git check`, and the pre-push guard runs it before every push (bin/hooks/pre-push/minimum-check).

## Decisions
- GitHub Actions keep only the status checks of a pull request; the release, the promotion and the split are made by the App from the developer machine, and the old callable release, sync and merge-split workflows are removed (concept git-workflow-plugin; D71).
- The master ruleset requires the status check named `check`, so the job keeps that name (bin/config/rulesets.yaml).

## Constraints
- A consuming repository takes a copy of status-checks.yml; a change here is a change for every repository that copied it.
