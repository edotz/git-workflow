## Scopes

| Scope | Kind | Purpose | Declared |
|---|---|---|---|
| shell-lib (bin/lib) | code | Plugin-local bash libraries sourced by the git modules through PLUGIN_ROOT: github and worktree, and the release-flow libraries check, component, token, tool and version | yes (the declared purpose names github.sh and worktree.sh only) |
| shell-modules (bin/modules) | code | Shell command modules: git (workflow-setup, branch protection, worktree, commit lint, release, promote, token service) and ide (vscode profiles and project setup) | yes |
| docker (.docker) | environment | Container images of the git-workflow plugin: the pinned tool image and the token service image, one Dockerfile with a stage per image | yes |
| github-workflows (.github/workflows) | ci | GitHub Actions workflows; the generated status-checks.yml is the pull-request check, the callable workflows are the old release and sync flow | yes |
| project (.agentic-os/project) | planning | The concepts, the plans and the project context | yes |
| agents, commands, skills (.agentic-os/*) | registration | The project's own capabilities; intentionally empty, only framework and adapter capabilities are enabled | yes |
| node (package.json) | code | Biome and commit message lint tooling and the token service dependency | no |

The root declaration with the trigger Dockerfile matches no file since the Dockerfile moved to .docker; its removal is the developer's to do.

## Structure

- bin/lib holds check.sh (105 lines), component.sh (301), github.sh (265), token.sh (145), tool.sh (226), version.sh (246) and worktree.sh (172); the plugin declares `provides: [modules, hooks]` and no lib surface (plugin.yaml; product.md). The modules source them as `${PLUGIN_ROOT}/bin/lib/<name>.sh`: release.sh sources tool, token, component, version and check; promote.sh sources tool and token (bin/modules/git/*.sh).
- bin/modules/git has 10 commands (branch-cleanup, branch-protection, lint-commit, promote, release, run-status, token-service, workflow-setup, workflow-status, worktree); bin/modules/ide has 3 (vscode-setup, vscode-teardown, vscode-profile); each domain lists its commands in a module.yaml.
- workflow-setup sources three heredoc template files from bin/modules/git/templates (branch-protection.sh, workflow-callers.sh, release-please.sh) and has the modes validate, --apply, --check and --init (workflow-setup.sh).
- Plugin settings are flat keys prefixed `PLUGIN_EDOTZ_GIT_WORKFLOW_`: MAIN_BRANCH, RELEASE_BRANCH, STALE_DAYS, VSCODE_PROFILES_DIR (bin/config/env.defaults). The pins of the tool image are unprefixed keys in .env.defaults; the plugin-root .env overrides them key by key (.env.defaults header).
- The plugin registers the hook keys pre-commit, pre-push and commit-msg, all of type guard; commit-msg runs `app git lint-commit` (bin/hooks/hooks.yaml, bin/hooks/commit-msg/conventional).
- Linters run through `toolchain.linters` of .agentic-os/project.yaml (node with Biome through biome.json, shell with shellcheck and .shellcheckrc); `app lint all full` runs them. package.json is `@edotz/git-workflow` 0.1.0, private, with the dependency `@octokit/auth-app` 8.3.1 and the devDependencies `@biomejs/biome` 2.6.5, `@commitlint/cli` and `@commitlint/config-conventional` ^21.2.4 and `shellcheck` ^1.1.0, locked in package-lock.json (lockfileVersion 3) and no scripts (package.json).
- .docker/Dockerfile has three stages: `fetch` (downloads the tool binaries and checks them), `tool` (git, jq, git-cliff, splitsh-lite, gh) and `token-service` (the Node token service, port 8790); docker-compose.yaml in the project root builds the tool and token-service targets (.docker/Dockerfile:3, 28, 42; docker-compose.yaml).
- .github/workflows holds the generated status-checks.yml (jobs commit-lint and stage-guard) and five reusable `_callable-` workflows (status-checks, release-please, post-release, sync-to-monorepo, merge-split-repo) that no workflow of this repository calls (.github/workflows/).
- .agentic-os/agents, commands and skills register no project capability (`[]` in their yaml) and enable 22 agents, 15 commands and 23 skills of the framework and adapter tiers (agents.json, commands.json, skills.json).

## Decisions

- Branch source: `.env.defaults` and `.env` are the source of truth; `.github/workflow.env` is a remnant of the old integration and the developer deletes it (developer's answer). The concept does not keep it: the component declaration replaces the workflow.env per package (CONCEPT Q41, D44) and the release branch is read from RELEASE_BRANCH (CONCEPT:65); the plan names it nowhere. Still reading it, to be changed: worktree.sh (lines 154-165, only `MAIN_BRANCH=` with a hardcoded `master` fallback), workflow-status.sh (17-19, optional), workflow-setup.sh (requires it for validate, --init and the generation of status-checks.yml and branch-protection.yaml), the exception in .gitignore line 5 and the workflow.env.*.example templates; branch-cleanup.sh reads only the plugin keys.
- Worktrees live in /home/ohoeft/worktrees; bin/lib/worktree.sh:22 still uses `${PROVIDER_CONFIG_DIR}/worktrees`. Reason: the developer's answer.
- github.sh and worktree.sh stay plugin-local by design, not in the framework lib. Reason: the developer's answer.
- The module.yaml-per-domain layout is a framework requirement. Reason: the developer's answer.
- Heredoc templates and the types single, monorepo and package are inherited from the framework and were not re-decided (developer's answer). The concept shrinks workflow-setup to config validation and `status-checks.yml`, and replaces the merge-commit-only branch protection by rulesets with squash merge in the production phase. Evidence: bin/modules/git/templates/*.sh, workflow-setup.sh, templates/branch-protection.sh.
- The generated status-checks.yml stays the pull-request check; the callable status-checks workflow is not the replacement (developer's answer; .github/workflows/status-checks.yml, _callable-status-checks.yml). Its header names workflow.env as the source, which goes with the file; the plan makes it a static file with one job named check (PLAN-plugin.md:331).
- vscode-setup prefers the vscode-server Project Manager path over the native one. Reason: the team works in WSL and remote (vscode-setup.sh, vscode-teardown.sh).
- Commitlint is installed per plugin root and run from node_modules/.bin. Reason: the lockfile pins the version (lint-commit.sh:16-19; developer's answer).
- The ten commit types, the disabled subject-case rule and the subject length of 100 are the team convention (commitlint.config.mjs; developer's answer).
- Local commit lint has to match CI: the Merge and Revert bypass in lint-commit.sh:13 is to be removed, the CI job commit-lint has none (developer's answer).
- The workflow-callers template runs `npm ci` and `npm run lint` although package.json has no lint script; it is stale and to be fixed (templates/workflow-callers.sh:115-116; developer's answer).
- The vscode-profiles.json mention in the vscode-setup.sh header is stale; the profiles directory is the only mechanism (developer's answer).
- The worktree.sh header requirement list (core.sh, json.sh) is stale from the move (worktree.sh:3; developer's answer).
- Module versions follow no convention (developer's answer).
- Docker: the container is a standing part of the project (developer's answer). By the concept it carries git, gh, git-cliff and splitsh-lite, has no entrypoint because `app` runs on the host, is defined with docker compose and the `.docker` directory, and modules call it through docker; the Ubuntu variant and the `bin/gh-wf` copy of the Dockerfile are gone (.docker/Dockerfile; concept).
- The base images are to be unified: the tool stages take IMAGE_BASE from the pins, the token-service stage pins node:22-bookworm-slim by digest in the Dockerfile and its digest is to move to the pins (developer's answer; .docker/Dockerfile:1, 42).
- The shebang is to be unified: every module script uses `#!/usr/bin/env bash`; the ide scripts and the git templates still use `#!/bin/bash` (developer's answer; bin/modules/ide/vscode-setup.sh:1).
- agents, commands and skills of the project are intentionally empty (developer's answer).
- The plugin bundles no LLM CLI: the commit message and the changelog summary come from `provider_run_prompt` on the host session, and the tool binaries are pinned by checksum (.docker/Dockerfile:11-26; concept).

## Environment

- Modules run as `bash $BU_ROOT/app <domain> <command>` (bin/modules/ide/module.yaml).
- `bash bin/app git workflow-setup [--apply] [--check]` validates or applies the generated files (workflow-setup.sh:3-4).
- Commit messages are linted with `app git lint-commit <file>`; commitlint is installed with `npm install` in the plugin root (lint-commit.sh:17).
- Lint: `bash ${BU_ROOT}/app lint all full` runs the declared linters (node, shell) and the framework checks; without `full` the mode is staged. Markdown and YAML files have no declared linter (.agentic-os/project.yaml:15-24).
- Compose commands take `--env-file .env.defaults` and then `--env-file .env` when it exists (.env.defaults header).
- CI: the job commit-lint uses `wagoid/commitlint-github-action@v6` with `commitlint.config.mjs` and `commitDepth: 1` (.github/workflows/_callable-status-checks.yml:20-34).
- Container: the tool image takes its base from IMAGE_BASE, has WORKDIR /workspace and carries git-cliff, splitsh-lite and gh pinned by version and checksum (.docker/Dockerfile:1-40; .env.defaults); the token-service image is node:22-bookworm-slim by digest, runs as user node and exposes port 8790 (.docker/Dockerfile:42-50).
- Required status check names the git module knows: commit-lint, biome, php-cs-fixer, shellcheck, eslint (workflow-setup.sh:STATUS_CHECK_DISPLAY_NAMES).

## Constraints

- A change to bin/lib or bin/modules is done when `bash ${BU_ROOT}/app lint domain full` exits 0 under .shellcheckrc (confirmed; it passes on 26 files today).
- Module scripts run under `set -euo pipefail` (proven: bin/modules/git/*.sh, bin/modules/ide/*.sh).
- Plugin setting keys start with `PLUGIN_EDOTZ_GIT_WORKFLOW_` and may not redefine a framework key (proven: bin/config/env.defaults:1).
- Generated files are never edited by hand; changes go through bin/modules/git/templates and workflow-setup (proven: the GENERATED headers).
- Commit messages follow the rules of commitlint.config.mjs: type enum, lower-case type and scope, subject non-empty, no trailing full stop, at most 100 characters (proven; CI job in _callable-status-checks.yml:31-34).
- Each library is sourced once through its guard variable `BU_STATE_<NAME>` and loads core.sh through `${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh`; worktree.sh needs git on PATH at load time, and a worktree is created only when the local base branch equals `origin/<base>` unless origin cannot be resolved (confirmed; proven: bin/lib/*.sh headers, worktree.sh:16, 119-121).
- token.sh keeps the installation token in the shell variable GH_TOKEN unexported and writes it to no file, log line or argument (confirmed; bin/lib/token.sh:6).
- branch-cleanup never deletes the main and release branches, main, master, develop, development, staging, production, `release-please--*` and `backport/*` (confirmed; branch-cleanup.sh:is_protected).
- Container: all developers use identical tool versions (confirmed); the tool image's base is pinned by digest and each download by checksum, empty build args fail the build, the binaries are linux amd64 only, and the token service installs production dependencies only and runs as a non-root user (proven: .docker/Dockerfile:11-26, 32, 45, 48; .env.defaults).
- Direct pull requests to the release branch 1.x fail unless the head branch starts with `release-please--`; the route is `/git:promote` (proven: .github/workflows/status-checks.yml:28-32).
