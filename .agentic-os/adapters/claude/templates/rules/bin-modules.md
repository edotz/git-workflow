---
paths:
  - "bin/modules/**"
---

# Shell modules

Shell command modules of the plugin: git (the daily loop start, commit, pr and check; rules-sync; release, promote, split, worktree, workflow status and setup, branch cleanup, branch protection, commit lint, token service) and ide (vscode profiles and project setup).

## Purpose and conventions
- Two module domains, git (17 commands) and ide (3 commands), each listed in a module.yaml; the module.yaml layout is a framework requirement (developer's answer).
- Commands run as `bash $BU_ROOT/app <domain> <command>` (bin/modules/ide/module.yaml).
- Module scripts run under `set -euo pipefail`.
- Plugin setting keys in bin/config/env.defaults start with `PLUGIN_EDOTZ_GIT_WORKFLOW_`. The branch settings are the exception: `GIT_WORKFLOW_MAIN_BRANCH` and `GIT_WORKFLOW_RELEASE_BRANCH` are defined in the project-root `.env`, which the framework loads (the process environment wins); scripts read them from the environment with `master` as the fallback in code (D49).

## Decisions
- workflow-setup is reduced to `validate`, which checks and prints the two branch settings; `--apply`, `--check` and `--init` are removed, and the rendering and preflight code is deleted (D50, T4.14).
- The branch-protection command and the scripts under bin/modules/git/templates are classic code inherited from the framework; rulesets through `rules-sync` with squash merge replace them and the old code is retired in P6 of PLAN-plugin; it is not fixed in place.
- vscode-setup prefers the vscode-server Project Manager path over the native one because the team works in WSL and remote (developer's answer).
- Commit lint must behave like CI: the Merge and Revert bypass in lint-commit.sh:13 is to be removed (developer's answer).
- The vscode-profiles.json reference in the vscode-setup.sh header is stale; the profiles directory is the only mechanism (developer's answer).

- The daily loop is `app git start <type> <name>`, `commit`, `pr` and `check`; each is registered in module.yaml and has a test under tests/git-<name>/ that builds a throwaway repository with an empty `.agentic-os` directory.
- Commands that run git or gh in the tool image do it through `tool_run`; the token of the developer is `gh auth token` (pr, branch-cleanup, the rules-sync dry run), the token of the App comes from `token_fetch` (rules-sync --apply).
- rules-sync skips a ruleset whose branch setting is unset and prints `skipped`; master always applies (D58).
- workflow-status counts the unreleased commits itself: `git_get_commit_details` and `git_conventional_commit_stats` of the framework library break on a quoted subject and drop the oldest commit.

## Environment
- `bash bin/app git workflow-setup [validate]` checks the branch settings (workflow-setup.sh).
- `app git check [component]` runs the minimum check of the components of components.yaml; the same check runs in the workflow .github/workflows/status-checks.yml (job `check`).
- Commit messages are linted with `app git lint-commit <file>`; install commitlint with `npm install` in the plugin root (lint-commit.sh).

## Constraints
- A change is done when shellcheck is clean (developer's answer).
- branch-cleanup counts a branch as merged when git cherry finds no unapplied commit, also as one squashed commit on the merge base, or when a merged pull request has it as head (gh through tool_run).
- branch-cleanup never deletes the main and release branches, main, master, develop, development, staging, production, `release-please--*` and `backport/*` (developer's answer, branch-cleanup.sh:is_protected).
