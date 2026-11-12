## Scopes

| Scope | Kind | Purpose | Declared |
|---|---|---|---|
| shell-lib (bin/lib) | code | Plugin-local bash libraries sourced by the git modules through PLUGIN_ROOT: github and worktree, and the release-flow libraries check, component, remote, rules, split, token, tool and version | yes |
| shell-modules (bin/modules) | code | Shell command modules: git (the daily loop start, commit, pr and check; rules-sync; release, promote, split; worktree; workflow status and setup; branch cleanup; commit lint; token service; shims) and ide (vscode profiles and project setup) | yes |
| docker (.docker) | environment | Container images of the git-workflow plugin: the pinned tool image and the token service image, one Dockerfile with a stage per image | yes |
| ci (.github/workflows) | ci | The one GitHub Actions workflow of the repository: status-checks.yml, the pull-request check | yes |
| project (.agentic-os/project) | planning | The concepts, the plans and the project context | yes |
| agents, commands, skills (.agentic-os/*) | registration | The project's own capabilities; intentionally empty, only framework and adapter capabilities are enabled | yes |
| node (package.json) | code | Biome and commit message lint tooling and the token service dependency | no |

The root declaration with the trigger Dockerfile matches no file since the Dockerfile moved to .docker; its removal is the developer's to do.

## Structure

- bin/lib holds check.sh (105 lines), component.sh (301), github.sh (188), remote.sh (74), rules.sh (121), split.sh (57), token.sh (145), tool.sh (226), version.sh (246) and worktree.sh (171); the plugin declares `provides: [modules, hooks, commands]` and no lib surface (plugin.yaml). The modules source them as `${PLUGIN_ROOT}/bin/lib/<name>.sh`: release.sh sources tool, token, component, version and check; promote.sh sources tool and token; split.sh sources tool, component, split and token (bin/modules/git/*.sh).
- bin/modules/git has 15 commands (branch-cleanup, check, commit, lint-commit, pr, promote, release, rules-sync, shims, split, start, token-service, workflow-setup, workflow-status, worktree); bin/modules/ide has 3 (vscode-setup, vscode-teardown, vscode-profile); each domain lists its commands in a module.yaml.
- workflow-setup has one mode, `validate`, which checks and prints the two branch settings (workflow-setup.sh). workflow-status reports as JSON the unreleased commits, the release branch position of every component and, in the field `runs`, the recent workflow runs, empty without gh, a credential or a network (workflow-status.sh).
- Plugin settings are flat keys prefixed `PLUGIN_EDOTZ_GIT_WORKFLOW_`: STALE_DAYS and VSCODE_PROFILES_DIR (bin/config/env.defaults). The branch settings `GIT_WORKFLOW_MAIN_BRANCH` and `GIT_WORKFLOW_RELEASE_BRANCH` and the stage and App id come from the environment and the project-root `.env`. The pins of the tool image are unprefixed keys in .env.defaults; the plugin-root .env overrides them key by key (.env.defaults header).
- The plugin registers the hook keys pre-push and commit-msg, both of type guard; commit-msg runs `app git lint-commit` and `app git shims` puts the shims of the two keys into a clone (bin/hooks/hooks.yaml, bin/hooks/commit-msg/conventional). The git pre-commit key, its mapping and its shim belong to agentic-os, which ships the pre-commit hook scripts.
- Linters run through `toolchain.linters` of .agentic-os/project.yaml (node with Biome through biome.json, shell with shellcheck and .shellcheckrc); `app lint all full` runs them. package.json is `@edotz/git-workflow` 0.1.0, private, with the dependency `@octokit/auth-app` 8.3.1 and the devDependencies `@biomejs/biome` 2.6.5, `@commitlint/cli` and `@commitlint/config-conventional` ^21.2.4 and `shellcheck` ^1.1.0, locked in package-lock.json (lockfileVersion 3) and no scripts (package.json).
- .docker/Dockerfile has three stages: `fetch` (downloads the tool binaries and checks them), `tool` (git, jq, git-cliff, splitsh-lite, gh) and `token-service` (the Node token service, port 8790); docker-compose.yaml in the project root builds the tool and token-service targets (.docker/Dockerfile:3, 28, 42; docker-compose.yaml).
- .github/workflows holds status-checks.yml only: one job `check` on every pull request, with the commit lint of the pull request, the lint of the pull request title and the checks that components.yaml declares (.github/workflows/status-checks.yml).
- Branch rules are rulesets, not classic protection: bin/config/rulesets.yaml defines `master` (squash merge only, the required check `check`, linear history, in the production stage), `release` and `legacy`, and `app git rules-sync` creates or updates them with the App; the App is a bypass actor (bin/config/rulesets.yaml; bin/lib/rules.sh).
- Releases, promotion and the split to the child repositories are made on the developer machine through `app git release`, `promote` and `split`, with an installation token of the GitHub App from the token service in a narrowed set per command (bin/config/token-service.json; bin/lib/token.sh).
- .agentic-os/agents, commands and skills register no project capability (`[]` in their yaml); the framework and adapter capabilities are enabled through agents.json, commands.json and skills.json.

## Decisions

- Branch source: `GIT_WORKFLOW_MAIN_BRANCH` and `GIT_WORKFLOW_RELEASE_BRANCH` of the project-root `.env`, which the framework loads at bootstrap (the process environment wins); a project `.env.defaults` is never loaded, and the fallback is `master` in code (PLAN-plugin D49). `.github/workflow.env` and its templates are deleted; the component declaration replaces it per package (CONCEPT Q41, D44). workflow-setup is reduced to `validate` (D50).
- Worktrees live in `<GIT_WORKFLOW_WORKTREE_DIR or $HOME/worktrees>/<repo-name>/<name>` (bin/lib/worktree.sh:86). Reason: the developer's answer.
- github.sh and worktree.sh stay plugin-local by design, not in the framework lib. Reason: the developer's answer.
- The module.yaml-per-domain layout is a framework requirement. Reason: the developer's answer.
- Repositories merge by squash and are protected by rulesets; the classic branch protection command, its templates and the generated workflow callers are retired (T6.7). The pull-request check is the static status-checks.yml with one job named `check` (D71).
- The release branch keeps its name per repository and is moved once to the release commit by `promote baseline`; legacy lines are frozen and change by pull request (D79 to D82). The split skips a child tag that sits at another commit and moves it never (D83). The token set `split` carries the workflows permission and no other command does (D84).
- vscode-setup prefers the vscode-server Project Manager path over the native one. Reason: the team works in WSL and remote (vscode-setup.sh, vscode-teardown.sh).
- Commitlint is installed per plugin root and run from node_modules/.bin. Reason: the lockfile pins the version (lint-commit.sh; developer's answer).
- The ten commit types, the disabled subject-case rule and the subject length of 100 are the team convention (commitlint.config.mjs; developer's answer).
- Local commit lint behaves like CI: commitlint decides alone and there is no Merge or Revert bypass (developer's answer; T6.15).
- The vscode-profiles.json mention in the vscode-setup.sh header is stale; the profiles directory is the only mechanism (developer's answer).
- The worktree.sh header requirement list (core.sh, json.sh) is stale from the move (worktree.sh:3; developer's answer).
- Module versions follow no convention (developer's answer).
- Docker: the container is a standing part of the project (developer's answer). By the concept it carries git, gh, git-cliff and splitsh-lite, has no entrypoint because `app` runs on the host, is defined with docker compose and the `.docker` directory, and modules call it through docker (.docker/Dockerfile; concept).
- The base images are to be unified: the tool stages take IMAGE_BASE from the pins, the token-service stage pins node:22-bookworm-slim by digest in the Dockerfile and its digest is to move to the pins (developer's answer; .docker/Dockerfile:1, 42).
- The shebang is to be unified: every module script uses `#!/usr/bin/env bash`; the ide scripts still use `#!/bin/bash` (developer's answer; bin/modules/ide/vscode-setup.sh:1).
- agents, commands and skills of the project are intentionally empty (developer's answer).
- The plugin bundles no LLM CLI: the commit message and the changelog summary come from `provider_run_prompt` on the host session, and the tool binaries are pinned by checksum (.docker/Dockerfile:11-26; concept).

## Environment

- Modules run as `bash $BU_ROOT/app <domain> <command>` (bin/modules/ide/module.yaml).
- `bash bin/app git workflow-setup [validate]` checks the branch settings (workflow-setup.sh).
- `bash bin/app git rules-sync --dry-run` shows the rulesets that would be created or updated; `--apply` needs `GIT_WORKFLOW_APP_ID` and the token service (rules-sync.sh).
- Commit messages are linted with `app git lint-commit <file>`; commitlint is installed with `npm install` in the plugin root (lint-commit.sh).
- Lint: `bash ${BU_ROOT}/app lint all full` runs the declared linters (node, shell) and the framework checks; without `full` the mode is staged. Markdown and YAML files have no declared linter (.agentic-os/project.yaml).
- Compose commands take `--env-file .env.defaults` and then `--env-file .env` when it exists (.env.defaults header).
- CI: the job `check` uses `wagoid/commitlint-github-action@v6` with `commitlint.config.mjs` (.github/workflows/status-checks.yml).
- Container: the tool image takes its base from IMAGE_BASE, has WORKDIR /workspace and carries git-cliff, splitsh-lite and gh pinned by version and checksum (.docker/Dockerfile:1-40; .env.defaults); the token-service image is node:22-bookworm-slim by digest, runs as user node and exposes port 8790 (.docker/Dockerfile:42-50).

## Constraints

- A change to bin/lib or bin/modules is done when shellcheck is clean under .shellcheckrc and `bash ${BU_ROOT}/app lint modules` exits 0.
- Module scripts run under `set -euo pipefail` (proven: bin/modules/git/*.sh, bin/modules/ide/*.sh).
- Plugin setting keys start with `PLUGIN_EDOTZ_GIT_WORKFLOW_` and may not redefine a framework key (proven: bin/config/env.defaults:1).
- Commit messages follow the rules of commitlint.config.mjs: type enum, lower-case type and scope, subject non-empty, no trailing full stop, at most 100 characters (proven; CI job `check` in status-checks.yml).
- Each library is sourced once through its guard variable `BU_STATE_<NAME>` and loads core.sh through `${BU_LIB:-${BASH_SOURCE[0]%/*}}/core.sh`; worktree.sh needs git on PATH at load time, and a worktree is created only when the local base branch equals `origin/<base>` unless origin cannot be resolved (confirmed; proven: bin/lib/*.sh headers).
- token.sh keeps the installation token in the shell variable GH_TOKEN unexported and writes it to no file, log line or argument (confirmed; bin/lib/token.sh:6).
- branch-cleanup never deletes the main and release branches, main, master, develop, development, staging, production, and the branch patterns of the old release train and backport, which stay protected in the code (confirmed; branch-cleanup.sh:is_protected).
- Container: all developers use identical tool versions (confirmed); the tool image's base is pinned by digest and each download by checksum, empty build args fail the build, the binaries are linux amd64 only, and the token service installs production dependencies only and runs as a non-root user (proven: .docker/Dockerfile:11-26, 32, 45, 48; .env.defaults).
- A pull request reaches `master` only by squash merge with the check `check` green; the release branch and the legacy branches change by pull request or by `promote` as the App (bin/config/rulesets.yaml).
