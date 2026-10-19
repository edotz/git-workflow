---
paths:
  - "bin/modules/**"
---

# Shell modules

Shell command modules of the plugin: git (workflow-setup, branch protection, worktree, commit lint) and ide (vscode profiles and project setup).

## Purpose and conventions
- Two module domains, git (7 commands) and ide (3 commands), each listed in a module.yaml; the module.yaml layout is a framework requirement (developer's answer).
- Commands run as `bash $BU_ROOT/app <domain> <command>` (bin/modules/ide/module.yaml).
- Module scripts run under `set -euo pipefail`.
- Plugin setting keys start with `PLUGIN_EDOTZ_GIT_WORKFLOW_` (bin/config/env.defaults:1).

## Decisions
- workflow-setup renders branch protection, workflow callers and release-please config from `.github/workflow.env` (types single, monorepo, package) through shell heredoc templates; both the source and the template form are inherited from the framework and not re-decided (developer's answer).
- Generated branch protection allows merge commits only, with auto-merge and delete-branch-on-merge; inherited from the framework, not re-decided (developer's answer).
- The branch source is `.github/workflow.env` where a project declares it, with env.defaults as the default; branch-cleanup reads only the plugin keys and has to follow this (developer's answer).
- vscode-setup prefers the vscode-server Project Manager path over the native one because the team works in WSL and remote (developer's answer).
- Commit lint must behave like CI: the Merge and Revert bypass in lint-commit.sh:13 is to be removed (developer's answer).
- The workflow-callers template runs `npm run lint` without a matching script; it is stale and to be fixed (developer's answer).
- The vscode-profiles.json reference in the vscode-setup.sh header is stale; the profiles directory is the only mechanism (developer's answer).

## Environment
- `bash bin/app git workflow-setup [--apply] [--check]` validates or applies the generated files (workflow-setup.sh:3-4).
- Commit messages are linted with `app git lint-commit <file>`; install commitlint with `npm install` in the plugin root (lint-commit.sh).

## Constraints
- A change is done when shellcheck is clean (developer's answer).
- Generated files (branch protection YAML, workflow callers) are never edited by hand; changes go through bin/modules/git/templates and workflow-setup (generated headers).
- branch-cleanup never deletes the main and release branches, main, master, develop, development, staging, production, `release-please--*` and `backport/*` (developer's answer, branch-cleanup.sh:is_protected).
