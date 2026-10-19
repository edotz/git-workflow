## Scopes

| Scope | Kind | Purpose | Declared |
|---|---|---|---|
| shell-lib (bin/lib) | code | Plugin-local bash libraries (github.sh, worktree.sh) sourced by the git modules through PLUGIN_ROOT | yes |
| shell-modules (bin/modules) | code | Shell command modules: git (workflow-setup, branch protection, worktree, commit lint) and ide (vscode profiles and project setup) | yes |
| docker (Dockerfile) | environment | Container image of the git-workflow tools | yes, at the project root with trigger Dockerfile |
| node (package.json) | code | Commit message lint tooling | no: the root declaration file holds one block per provider and docker owns it |

## Structure

- bin/lib holds github.sh (266 lines) and worktree.sh (173 lines); the plugin declares `provides: [modules, hooks]` and no lib surface (plugin.yaml; product.md).
- bin/modules/git has 7 commands (branch-cleanup, branch-protection, lint-commit, run-status, workflow-setup, workflow-status, worktree); bin/modules/ide has 3 (vscode-setup, vscode-teardown, vscode-profile); each domain lists its commands in a module.yaml.
- workflow-setup sources three heredoc template files from bin/modules/git/templates (branch-protection.sh, workflow-callers.sh, release-please.sh) and has the modes validate, --apply, --check and --init (workflow-setup.sh).
- Plugin settings are flat keys prefixed `PLUGIN_EDOTZ_GIT_WORKFLOW_`: MAIN_BRANCH, RELEASE_BRANCH, STALE_DAYS, VSCODE_PROFILES_DIR (bin/config/env.defaults).
- The plugin registers the hook keys pre-commit, pre-push and commit-msg, all of type guard; commit-msg runs `app git lint-commit` (bin/hooks/hooks.yaml, bin/hooks/commit-msg/conventional).
- Node is used only for commit message linting: package.json is `@edotz/git-workflow` 0.1.0, private, with the devDependencies `@commitlint/cli` and `@commitlint/config-conventional` ^20.4.1, locked in package-lock.json (lockfileVersion 3) and no scripts (package.json).
- The Dockerfile holds two complete multi-stage variants, an Ubuntu 24.04 one (lines 1-63) and a node:22-bookworm-slim one (lines 67-126), and is untracked (Dockerfile).

## Decisions

- Branch source: a project declares its branches in `.github/workflow.env`; env.defaults holds the defaults. worktree.sh (lines 158-165) reads only `MAIN_BRANCH=` there with a hardcoded `master` fallback, and branch-cleanup.sh reads only the plugin keys; both have to follow this. Reason: the developer's answer.
- Worktrees live in /home/ohoeft/worktrees; bin/lib/worktree.sh:22 still uses `${PROVIDER_CONFIG_DIR}/worktrees`. Reason: the developer's answer.
- github.sh and worktree.sh stay plugin-local by design, not in the framework lib. Reason: the developer's answer.
- The module.yaml-per-domain layout is a framework requirement. Reason: the developer's answer.
- Heredoc templates, `.github/workflow.env` as the single source with the types single, monorepo and package, and merge-commit-only branch protection are inherited from the framework and were not re-decided (developer's answer). Evidence: bin/modules/git/templates/*.sh, workflow-setup.sh, templates/branch-protection.sh.
- vscode-setup prefers the vscode-server Project Manager path over the native one. Reason: the team works in WSL and remote (vscode-setup.sh, vscode-teardown.sh).
- Commitlint is installed per plugin root and run from node_modules/.bin. Reason: the lockfile pins the version (lint-commit.sh:16-19; developer's answer).
- The ten commit types, the disabled subject-case rule and the subject length of 100 are the team convention (commitlint.config.mjs; developer's answer).
- Local commit lint has to match CI: the Merge and Revert bypass in lint-commit.sh:13 is to be removed, the CI job commit-lint has none (developer's answer).
- The workflow-callers template runs `npm ci` and `npm run lint` although package.json has no lint script; it is stale and to be fixed (templates/workflow-callers.sh:115-116; developer's answer).
- The vscode-profiles.json mention in the vscode-setup.sh header is stale; the profiles directory is the only mechanism (developer's answer).
- The worktree.sh header requirement list (core.sh, json.sh) is stale from the move (worktree.sh:3; developer's answer).
- Module versions follow no convention (developer's answer).
- Docker: the node-slim variant is the intended one and the Ubuntu variant and the duplicated Alpine builder stages are leftovers; the container runs as the node user; `bin/gh-wf` is replaced by the framework `app`; the container is a standing part of the project and the doc names (Dockerfile.git-workflow, git-workflow-suite:latest) are outdated (Dockerfile; 260903-git-workflow.md; developer's answer).
- Pinned prebuilt tool binaries and bundling both LLM CLIs (Gemini CLI via npm, Claude Code via install script) were not decided; they came with the draft (Dockerfile:9-16, 53-55; developer's answer).

## Environment

- Modules run as `bash $BU_ROOT/app <domain> <command>` (bin/modules/ide/module.yaml).
- `bash bin/app git workflow-setup [--apply] [--check]` validates or applies the generated files (workflow-setup.sh:3-4).
- Commit messages are linted with `app git lint-commit <file>`; commitlint is installed with `npm install` in the plugin root (lint-commit.sh:17).
- CI: the job commit-lint uses `wagoid/commitlint-github-action@v6` with `commitlint.config.mjs` and `commitDepth: 1` (.github/workflows/_callable-status-checks.yml:20-34).
- Container: node:22-bookworm-slim, WORKDIR /workspace, git-cliff v2.8.0 and splitsh-lite v1.0.1 pinned in the download URLs (Dockerfile:9-16, 99-126).
- Required status check names the git module knows: commit-lint, biome, php-cs-fixer, shellcheck, eslint (workflow-setup.sh:STATUS_CHECK_DISPLAY_NAMES).

## Constraints

- A change to bin/lib or bin/modules is done when shellcheck is clean (confirmed).
- Module scripts run under `set -euo pipefail` (proven: bin/modules/git/*.sh, bin/modules/ide/*.sh).
- Plugin setting keys start with `PLUGIN_EDOTZ_GIT_WORKFLOW_` and may not redefine a framework key (proven: bin/config/env.defaults:1).
- Generated files are never edited by hand; changes go through bin/modules/git/templates and workflow-setup (proven: the GENERATED headers).
- Commit messages follow the rules of commitlint.config.mjs: type enum, lower-case type and scope, subject non-empty, no trailing full stop, at most 100 characters (proven; CI job in _callable-status-checks.yml:31-34).
- Each library is sourced once through its guard variable, worktree.sh needs git on PATH at load time, and a worktree is created only when the local base branch equals `origin/<base>` unless origin cannot be resolved (proven: github.sh:7-11, worktree.sh:7-11, 16, 119-121).
- branch-cleanup never deletes the main and release branches, main, master, develop, development, staging, production, `release-please--*` and `backport/*` (confirmed; branch-cleanup.sh:is_protected).
- Container: all developers use identical tool versions (confirmed); Node major version 22 and base images pinned by tag (proven: Dockerfile:1, 19, 67, 85, 99).
