# Product

## Purpose

`edotz.git-workflow` is an agentic-os plugin that owns the git and GitHub workflow ecosystem of the edotz projects.
The agentic-os framework carries none of it: a project declares the plugin under `plugins:` in its
`.agentic-os/project.yaml` and gets the capabilities below.

What the plugin provides today (`plugin.yaml`: `provides: [modules, hooks, commands]`):

- The `git` command domain (`bin/modules/git/`): the daily loop `start`, `commit`, `pr` and `check`; `rules-sync`,
  `release`, `promote` and `split`; `worktree`, `branch-cleanup`, `lint-commit`, `shims`, `token-service`,
  `workflow-setup` and `workflow-status` (which also reports the recent workflow runs).
- The git hook host: the registry of the keys `pre-commit`, `commit-msg` and `pre-push` (`bin/hooks/hooks.yaml`) and
  how git fires them (`adapters/git/hooks/hooks.yaml`), plus the hook `commit-msg/conventional`.
- Conventional commit validation: `git lint-commit` runs commitlint with the config `commitlint.config.mjs`. The
  plugin owns the config and the `@commitlint/*` packages (`package.json`); a consuming project keeps neither.
- The libraries of the workflow in `bin/lib/` (`github.sh`, `worktree.sh` and the release-flow libraries `check`,
  `component`, `remote`, `rules`, `split`, `token`, `tool` and `version`) and the static pull-request check
  `.github/workflows/status-checks.yml`.

Why it exists: the git ecosystem is a separate concern with its own release cycle, and the framework stays provider-
and workflow-agnostic.

How it works (concept `git-workflow-plugin`, built by PLAN-plugin): a local workflow behind `app git <command>` replaces
the cascading GitHub Actions. A release is made on `master` as one commit with its tag, previewed by a dry run and
pushed by a GitHub App, the only actor that releases; the release branch follows by a separate fast-forward `promote`,
and legacy branches change by PR. Changelog with `git-cliff`, rulesets synced through the GitHub API. A monorepo is a set
of components that are released on their own, and a component marked `split` is split with `splitsh-lite` and pushed to
its repository from the developer machine. The commit message and the changelog summary come from `provider_run_prompt`
on the host session, so the plugin bundles no LLM CLI. The tools run from a pinned image through docker, so every
developer uses the same binaries. GitHub Actions keep only the status checks of a pull request.

## Stack

- Bash on the agentic-os framework: modules, hooks and plugin-local libraries; `git`, `gh`, `jq`, `yq`, `envsubst`.
- Node packages for commit validation: `@commitlint/cli` and `@commitlint/config-conventional` (20.x).
- In the tool image: `splitsh-lite`, `git-cliff` and `gh` in a pinned image built with docker compose; no LLM CLI and
  no Node in the image.

## Conventions

- A plugin script gets `PLUGIN_NAME` and `PLUGIN_ROOT`; it reaches its own files through `PLUGIN_ROOT`
  (`${PLUGIN_ROOT}/bin/lib/<name>.sh`) and the framework through `BU_ROOT` and `BU_LIB`. The plugin has no `lib`
  surface, so the libraries are plugin-local.
- Surfaces live where the framework looks for them: modules in `bin/modules/<domain>/`, hooks and their registry in
  `bin/hooks/`, the host mapping in `adapters/<host>/hooks/`.
- The framework rules of `bash-framework` and `bash-utility` apply: strict mode, `if/fi` instead of `[[ ]] &&`,
  library-first, `return 0` in libraries, output through `print_*`, `die` and `logger_*`.
- Commit messages follow Conventional Commits: types feat, fix, docs, style, refactor, perf, test, build, ci, chore;
  subject at most 100 characters, not empty, no trailing full stop; type and scope lower-case.

## Definition of Done

- The touched script passes `lint domain` and `lint modules` of the framework, run under `env -i HOME="$HOME"
  PATH="$PATH"` because the tool shell exports functions that mask missing sources.
- The command runs once for real, and a changed hook registry or mapping passes `hooks sync` without a diff.
- A command has a test under `tests/git-<name>/` that builds a throwaway repository and leaves the machine untouched.

## Architectural Invariants

- The plugin owns the whole git ecosystem. The framework keeps only the generic `bin/lib/git.sh`; it has no `git`
  domain, no git adapter and no commitlint config or package.
- Git is a hook host like a provider. The registry (`bin/hooks/hooks.yaml`) and the mapping
  (`adapters/git/hooks/hooks.yaml`) are both here; a plugin hook with the same event and name as a hook of a lower
  tier fails with exit 3.
- Every project that uses the plugin defines `GIT_WORKFLOW_MAIN_BRANCH` and `GIT_WORKFLOW_RELEASE_BRANCH` in its
  project-root `.env`; the fallback in code is `master` for both, so a project without a separate release branch
  releases from the main branch. The keys of `bin/config/env.defaults` are `PLUGIN_EDOTZ_GIT_WORKFLOW_STALE_DAYS` and
  `..._VSCODE_PROFILES_DIR`.
- One source of commit validation: `commitlint.config.mjs` of this plugin. No second copy in a consuming project.
- No hardcoded framework layout: a path comes from `PLUGIN_ROOT`, `BU_ROOT` or a framework function.
- The workflow runs on the developer machine, an async cloud job never decides a
  release, and a release is one atomic commit with its tag.
