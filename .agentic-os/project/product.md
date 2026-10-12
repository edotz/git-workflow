# Product

## Purpose

`edotz.git-workflow` is an agentic-os plugin that owns the git and GitHub workflow ecosystem of the edotz projects.
The agentic-os framework carries none of it: a project declares the plugin under `plugins:` in its
`.agentic-os/project.yaml` and gets the capabilities below.

What the plugin provides today (`plugin.yaml`: `provides: [modules, hooks]`), moved as-is from the framework:

- The `git` command domain (`bin/modules/git/`): `branch-cleanup`, `branch-protection`, `run-status`,
  `workflow-setup`, `workflow-status`, `worktree`, and `lint-commit`.
- The git hook host: the registry of the keys `pre-commit`, `commit-msg` and `pre-push` (`bin/hooks/hooks.yaml`) and
  how git fires them (`adapters/git/hooks/hooks.yaml`), plus the hook `commit-msg/conventional`.
- Conventional commit validation: `git lint-commit` runs commitlint with the config `commitlint.config.mjs`. The
  plugin owns the config and the `@commitlint/*` packages (`package.json`); a consuming project keeps neither.
- The workflow material: `.github/` workflow blueprints, `workflow.env.{single,package,monorepo}.example`, and the
  libraries `bin/lib/github.sh` and `bin/lib/worktree.sh`.

Why it exists: the git ecosystem is a separate concern with its own release cycle, and the framework stays provider-
and workflow-agnostic. Parts of the moved ecosystem are stale; they stay unchanged until the redesign replaces them.

Direction (concept document `260903-git-workflow.md`, not built yet): a local CLI (working title `gh-wf`) replaces the
cascading GitHub Actions. Split of a monorepo with `splitsh-lite` and push to the child repositories from the
developer machine, changelog with `git-cliff`, commit message and changelog summary from a headless LLM call
(`claude -p`, `gemini -p`), rulesets synced through the GitHub API, release as one atomic commit with tag, promotion
between `master`, the release branch and legacy branches. The toolchain ships in a Docker image with a host wrapper
(`git-wf`), so every developer runs the same binaries. GitHub Actions keep only the status checks of a pull request.

## Stack

- Bash on the agentic-os framework: modules, hooks and plugin-local libraries; `git`, `gh`, `jq`, `yq`, `envsubst`.
- Node packages for commit validation: `@commitlint/cli` and `@commitlint/config-conventional` (20.x).
- Planned by the concept document: `splitsh-lite`, `git-cliff`, Node 22 LTS, `claude` and `gemini` CLI, Docker.

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

- The touched script passes `lint shell` and `lint modules` of the framework, run under `env -i HOME="$HOME"
  PATH="$PATH"` because the tool shell exports functions that mask missing sources.
- The command runs once for real, and a changed hook registry or mapping passes `hooks sync` without a diff.
- A change to a moved file stays a move unless the task says redesign: no fix of stale behaviour on the way.

## Architectural Invariants

- The plugin owns the whole git ecosystem. The framework keeps only the generic `bin/lib/git.sh`; it has no `git`
  domain, no git adapter and no commitlint config or package.
- Git is a hook host like a provider. The registry (`bin/hooks/hooks.yaml`) and the mapping
  (`adapters/git/hooks/hooks.yaml`) are both here; a plugin hook with the same event and name as a hook of a lower
  tier fails with exit 3.
- Every project that uses the plugin defines `MAIN_BRANCH` and `RELEASE_BRANCH`. The fallbacks are the keys
  `PLUGIN_EDOTZ_GIT_WORKFLOW_MAIN_BRANCH` and `..._RELEASE_BRANCH` in `bin/config/env.defaults`, together with
  `..._STALE_DAYS`. There is no release strategy yet: every change goes to the main branch (`master`), so the release
  branch defaults to the main branch too.
- One source of commit validation: `commitlint.config.mjs` of this plugin. No second copy in a consuming project.
- No hardcoded framework layout: a path comes from `PLUGIN_ROOT`, `BU_ROOT` or a framework function.
- Direction, once the redesign lands: the workflow runs on the developer machine, an async cloud job never decides a
  release, and a release is one atomic commit with its tag.
