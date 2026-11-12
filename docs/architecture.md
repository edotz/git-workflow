# git-workflow plugin: architecture

This manual is for the maintainers of the plugin. It describes how the code is laid out, how a command reaches git, GitHub and the tool image, how tokens are issued, how hooks and slash commands are shipped, how the tests run and how to extend the plugin. For what the commands do, read [Overview](overview.md) and [Command reference](command-reference.md).

Paths are relative to the plugin root unless they are absolute.

## Repository layout

```text
edotz.git-workflow/
  plugin.yaml                     what the plugin tells its host: name, version, provides, adapters
  components.yaml                 the plugin's own components (one: git-workflow, version none)
  bin/
    modules/git/                  one script per app git command, module.yaml (the registry)
    modules/ide/                  the ide domain: VS Code worktree setup and profiles
    lib/                          plugin libraries, sourced by the modules
    config/                       env.defaults, rulesets.yaml, token-service.json, cliff.toml
    hooks/                        hook scripts, one file per event and name, plus hooks.yaml
  adapters/git/hooks/hooks.yaml   the mapping of the hook keys to git events
  .git-templates/hooks/           the shims that git runs (commit-msg, pre-push)
  .docker/Dockerfile              the tool image (target tool) and the token service image
  docker-compose.yaml             builds the tool image and the token service container
  .env.defaults                   the pins of the tool image (digests, versions, checksums)
  commands/
    commands.yaml                 registration of the slash commands (namespace git, type tool)
    blueprints/tool-dispatch/     the body of each slash command: one bash line
  tests/<area>/                   the tests, one area per command or library
  .github/workflows/status-checks.yml   the CI of the plugin and of the consuming projects
  commitlint.config.mjs           the conventional commit rules
  biome.json, .shellcheckrc       formatter and shellcheck settings (biome is not run by CI)
  package.json                    commitlint, shellcheck, biome, @octokit/auth-app
  .vscode/profiles/               VS Code profiles used by the ide module
  .agentic-os/                    the plugin repository's own framework project tier (planning, concepts); not shipped
  .claude/                        runtime state of Claude Code in this repository; ignored
```

`.agentic-os/` is the framework project tier of this repository, used to develop the plugin itself. The plugin does not ship it.

## How a command is dispatched

1. The framework's `app` resolves `app git <command>` through the plugin registry: `plugin.yaml` declares `provides: [modules, hooks, commands]`, and `bin/modules/git/module.yaml` lists the commands.
2. When the entry point is a plugin file, the framework's bootstrap exports `PLUGIN_NAME`, `PLUGIN_ROOT` and `PLUGIN_LIB=<plugin root>/bin/lib` (`bootstrap_dispatch` in the framework's `lib/bootstrap.sh`). The plugin code relies on these three variables.
3. The module sources the framework libraries (`core.sh`, `cli.sh`, `git.sh`, `json.sh`, `yaml.sh`, `files.sh`, `output.sh`, `provider.sh`, and so on, as needed) from `BU_LIB`, then the plugin libraries from `PLUGIN_LIB`.
4. The module calls `cli_set_spec`, declares its flags and options with `cli_add_flag` and `cli_add_option`, runs `cli_parse "$@"` and ends with `main "$@"`.
5. Errors leave through `die`, `die_with <code>` or the code returned by a library. The exit codes are the framework's:

| Code | Name | Use in this plugin |
|---|---|---|
| 0 | `BU_EXIT_OK` | Success, including a no-op such as "nothing to release" |
| 1 | `BU_EXIT_FAILURE` | Runtime failure, and the default of `die`: a push, an API call or a git command failed; a red minimum check (`release`, `pr`, `check`) |
| 2 | `BU_EXIT_USAGE` | Wrong arguments, a mode not given, an unknown type or stage |
| 3 | `BU_EXIT_CONFIG` | `components.yaml` refused, a setting or a ruleset invalid, git-cliff gave no version, pnpm missing for a `workspace` component |
| 4 | `BU_EXIT_NOT_FOUND` | A file, a component, a tag or a remote missing |

Modules print their output with the framework's `print_*` helpers. A function whose stdout a caller captures marks its `echo` or `printf` with `# out:return`, the framework's convention for the output lint.

## Modules

One line per script in `bin/modules/git/`. The name is the `app git` command; the `module.yaml` description is the registry text.

| Script | Command | What it does |
|---|---|---|
| `start.sh` | `start` | Creates `<type>/<name>` from the main branch and switches the checkout to it (`branch_create`), refusing a branch that exists locally or on origin |
| `commit.sh` | `commit` | Stages the paths, drafts or takes the message, lints it with `lint-commit.sh`, asks for confirmation unless `--yes` with `--message`, commits as the developer; restores the index when the commit fails |
| `lint-commit.sh` | `lint-commit` | Runs the commitlint binary of `node_modules` on one commit message file with `commitlint.config.mjs` |
| `check.sh` | `check` | Runs `check_minimum` for every component or one named; prints `<name>: ok` or `<name>: failed`; writes nothing |
| `pr.sh` | `pr` | Refuses the main branch and a red minimum check, lints the title, then pushes and opens the pull request with `gh` as the developer |
| `release.sh` | `release` | Plans the components to release (`version_next`), checks them, prints the dry run or applies: release commit, tag, push, GitHub Release as the App |
| `promote.sh` | `promote` | Moves the release branch to the commit of a release tag: fast forward, or baseline mode with `--confirm`; the App pushes |
| `split.sh` | `split` | Dry run: child head, ancestry and tree difference per split component. Apply: one child per run, branch and component tags pushed as the App |
| `rules-sync.sh` | `rules-sync` | Builds each ruleset with `rules_json` and creates or updates it through the rulesets API; the dry run reads only; reports foreign rulesets and classic protection that cover a managed branch |
| `shims.sh` | `shims` | Copies the shims of `.git-templates/hooks` into the git hooks directory; `--check` reports only; leaves a file without the shim marker alone |
| `workflow-status.sh` | `workflow-status` | Prints JSON: the sync of the release branch, per component the latest tag, the commits since it, the release branch position, and recent workflow runs |
| `workflow-setup.sh` | `workflow-setup` | Validates `GIT_WORKFLOW_MAIN_BRANCH` and `GIT_WORKFLOW_RELEASE_BRANCH` (no whitespace) and prints them |
| `worktree.sh` | `worktree` | Lists, creates (`--start`) or prunes worktrees |
| `branch-cleanup.sh` | `branch-cleanup` | Analyses local and remote branches as merged, stale or active, prints them, and deletes the merged ones after the confirmation: only what git proves applied to the main branch, never a protected or legacy branch, remote branches only on github.com with a fetch and a lease |
| `token-service.mjs` | `token-service` | Node HTTP service that issues installation tokens; see [Token path](#token-path) |

The ide domain (`bin/modules/ide/`, `module.yaml` with domain `ide`) holds three scripts that are not part of the git workflow: `vscode-setup.sh` writes the title bar colour and a Project Manager entry for a worktree, `vscode-teardown.sh` removes that entry, and `vscode-profile.sh` composes and decomposes `.code-profile` files. Their default profiles directory is `.vscode/profiles` of the plugin, overridable with `PLUGIN_EDOTZ_GIT_WORKFLOW_VSCODE_PROFILES_DIR`.

## Libraries

Libraries are in `bin/lib/`. Each has a guard variable `BU_STATE_<NAME>` against double sourcing, sources `core.sh` and the libraries it needs, and documents its functions with the framework's header format (Args, Returns, Exits, Example).

| Library | Functions | What it does |
|---|---|---|
| `tool.sh` | `tool_image_ensure`, `tool_run` | Reads the pins, builds or reuses the tool image, runs one tool in an ephemeral container |
| `token.sh` | `token_fetch`, `token_drop` | Requests an installation token from the token service into `GH_TOKEN`, and drops it |
| `component.sh` | `component_load`, `component_names`, `component_root`, `component_tag_prefix`, `component_paths`, `component_field` | Validates `components.yaml` with one jq program, fills the defaults, answers queries; `component_paths` asks pnpm for `workspace` components |
| `version.sh` | `version_next`, `version_tag`, `version_write`, `version_cliff`, `version_latest_tag`, `version_notes_args` | Counts the bump with git-cliff over the range after the latest stable tag, writes version files, runs git-cliff for the notes and the CHANGELOG |
| `check.sh` | `check_minimum` | Lints the subjects since the latest tag with `lint-commit.sh`, then runs each declared check from the repository root; every step runs, every failure is printed |
| `rules.sh` | `rules_load`, `rules_names`, `rules_json` | Reads `bin/config/rulesets.yaml` as JSON and builds one ruleset for a stage in the GitHub body format |
| `split.sh` | `split_head` | Runs splitsh-lite in the tool image on the first path of a component and returns the split head |
| `remote.sh` | `remote_slug`, `remote_on_github`, `remote_identity` | Reads `owner/name` from a remote URL, tells whether the remote is on github.com, and reads the developer's `user.name` or `user.email`; no network, no token |
| `branch.sh` | `branch_create` | Creates a branch at the head of the main branch and switches to it without an upstream; refuses when the local main branch is not in sync with origin |
| `worktree.sh` | `worktree_create`, `worktree_get_path`, `worktree_prune`, `worktree_resolve_base_branch` | Worktree location `<dir>/<repo>/<name with / as ->`, creation from the main branch, refusal when the local main branch is not in sync with origin |
| `github.sh` | `github_ensure_authenticated`, `github_get_runs` | Reads workflow runs with `gh`; only `workflow-status` uses it |

### Contracts between modules and libraries

- **Loading.** A library is loaded once per process. A module loads `component.sh` before any call that reads components, and calls `component_load "${PROJECT_ROOT}/components.yaml"` itself. Calls run from the repository root.
- **Return values.** A function returns a value on stdout (captured by the caller, marked `# out:return`) or in a documented global: `SPLIT_HEAD` (`split.sh`), `_VERSION_*` (private to `version.sh`), `VERSION_NOTES_ARGS` (`version.sh`), `RULES_DOC` (`rules.sh`), `GH_TOKEN` (`token.sh`). A caller that needs the global must not call the function inside `$( )`, because the assignment is lost in the subshell. `token_fetch` says so in its header.
- **Status codes.** `version_next` returns 1 for "no commit of the component counts" and never uses 1 for an error. `release.sh` tells that status apart from errors, so a missing bump is not reported as a failure.
- **Errors.** Libraries stop through `die` or `die_with`. A module decides what the user sees; it does not catch a library error except where a status code is part of the contract (above).
- **Stdin.** `tool_run` forwards stdin when it is not a terminal. A caller in a `while read` loop must redirect the tool with `</dev/null`, or the tool reads the loop's input.
- **Remote writes.** Only the four commands that write release state use `token_fetch`: `release` and `promote` (contents set), `split` (split set), `rules-sync` (administration set). Each calls `token_drop` before it returns.

## How a command reaches a tool

Most git, gh, git-cliff and splitsh-lite calls go through `tool_run`:

```bash
tool_run git rev-parse --verify --quiet "refs/tags/${tag}^{commit}" </dev/null
```

`tool_run` does the following:

1. Calls `tool_image_ensure`, which requires `docker`, loads the pins and derives the image tag.
2. Finds the repository around the current directory without starting a process. For a linked worktree it also finds the common git directory above the worktree's `.git` file.
3. Runs `docker run --rm` with `--platform` from the pin `IMAGE_PLATFORM`, `--user <uid>:<gid>` of the caller, the working directory set to the caller's `$PWD`, a `tmpfs` at `/tmp/tool-home` as `HOME`, `safe.directory=*` through `GIT_CONFIG_*`, and `-i` when stdin is not a terminal.
4. Mounts the repository top, and the common git directory when it differs, with `--mount type=bind,src=<path>,dst=<path>` at the same path as on the host. A comma in a path is refused, because the mount syntax would break.
5. Passes `GH_TOKEN` by name (`-e GH_TOKEN`), so the value is not on the command line.
6. Runs the tool. The image has no entrypoint, so the tool name is the command.

**The tool image.** `.docker/Dockerfile` has three stages: `fetch` downloads git-cliff, splitsh-lite and gh and checks each against a pinned checksum; `tool` installs `ca-certificates`, `jq` and the pinned `git` package and copies the three binaries to `/usr/local/bin`; `token-service` is the Node 22 image of the service. The base image is pinned by digest.

**The image tag.** `tool_image_ensure` hashes the Dockerfile and the values of the nine pin keys (`TOOL_PIN_KEYS` in `tool.sh`): `IMAGE_BASE`, `IMAGE_PLATFORM`, `GIT_CLIFF_VERSION`, `GIT_CLIFF_SHA512`, `SPLITSH_VERSION`, `SPLITSH_SHA256`, `GH_VERSION`, `GH_SHA256`, `GIT_APT_VERSION`. The tag is `edotz-git-workflow-tools:<first 12 hex digits>`. If the tag does not exist, it runs `docker compose -f docker-compose.yaml build tools` and tags the result. A change of any pin or of the Dockerfile means a new tag and a new build; the old images stay.

**The pins.** `.env.defaults` in the plugin root gives the defaults. A `.env` in the plugin root overrides them key by key, only for the nine pin keys. A missing pin stops the command.

**No host fallback for the tools.** The git, gh, git-cliff and splitsh-lite calls never fall back to a host binary: when Docker is missing, `tool_run` stops. Some steps do use the host git directly, and they are the exceptions to know about: the minimum check (`check_minimum`, reads the commits), the remote and identity readers (`remote.sh`), the worktree library (`worktree_create` runs `git worktree add` on the host), and the framework helpers `pr.sh` calls to list commit subjects. `lint-commit.sh` runs the commitlint of the plugin's `node_modules`, which is also on the host. The image pins keep the tool versions identical for every developer.

**Pushes from the container.** The pushes of `release`, `promote`, `split` and `pr` pass `-c core.hooksPath=/dev/null`, so the shims of the clone do not run inside the image (the shims call `agentic-os`, which the image lacks), and `-c credential.helper=!gh auth git-credential`, so `gh` inside the container gives the token from `GH_TOKEN` to git.

## Token path

```text
module (release, promote, split, rules-sync)
  token_fetch <owner/name> <set>
    |  gh auth token                    the developer's own login, read on the host
    |  POST ${TOKEN_SERVICE_URL:-http://127.0.0.1:${TOKEN_SERVICE_PORT:-8790}}/token
    |     body {"repo": "...", "set": "..."} (curl reads url, header, body from a pipe)
    v
token service (bin/modules/git/token-service.mjs)
    1. the request must be POST /token with a bearer token; the body may not exceed 4096 characters
    2. set must be a key of bin/config/token-service.json; repo must be owner/name
    3. owner must be the organisation (config org, or TOKEN_SERVICE_ORG)  else 403 repository not in the organisation
    4. GET /user with the developer's token gives a login               else 401 login not accepted
    5. GET /user/memberships/orgs/<org> must be active                  else 403 not a member
    6. App JWT -> GET /repos/<owner>/<name>/installation                else 404 repository not installed
    7. installation token for that one repository, with the set's permissions (auto-refreshing)
    8. log line "issued login=... repo=... set=..." (no token), reply {token, expires_at, permissions, repository}
    v
token_fetch sets GH_TOKEN (not exported); token_drop unsets it
```

The shell side never writes the developer token or the installation token to a file, to a log line or to an argument: the curl options, which hold the developer token in the Authorization header, travel on stdin, and `token_fetch` empties them after the request. A failed request leaves no `GH_TOKEN` set, because `token_fetch` drops the old one before the request.

**Permission sets.** `bin/config/token-service.json` names the sets; the keys are the only values a client may ask for:

| Set | Permissions requested | Used by |
|---|---|---|
| `contents` | contents: write | `release`, `promote` |
| `split` | contents: write, workflows: write | `split` |
| `administration` | administration: write | `rules-sync` |

The service's error replies are `400` (set unknown, repository not owner/name, body not JSON), `401`, `403`, `404`, `413` (body above 4096 bytes), and `502` with the text "token service failed" for an unexpected error. The service logs the refusal reason, never a token.

**Running the service.** Two ways, both needing the App's ID and the path of its private key in the environment (variable names only: `TOKEN_SERVICE_APP_ID`, `TOKEN_SERVICE_KEY_PATH`):

- `bash app git token-service` runs the script with `node` on the host and listens on `TOKEN_SERVICE_HOST` (default `127.0.0.1`) at `TOKEN_SERVICE_PORT` (default 8790). The script refuses to start when the key file does not contain a private key.
- `docker compose` builds the `token-service` target and runs it with a read-only root filesystem, `no-new-privileges`, the key file mounted read-only at a fixed path inside the container, and the port published on `127.0.0.1` only. The key is never copied into an image. The client uses the same URL either way.

Hosting, key custody and the permission design belong to [GitHub App and token service](github-app-and-token-service.md).

## Hooks and shims

Three layers, each with a different owner:

1. **Git events.** `bin/hooks/hooks.yaml` declares the hook keys of the plugin: `commit-msg` and `pre-push`, all of type `guard`. `adapters/git/hooks/hooks.yaml` maps each key to its git event (`targets[0].event`), says that it blocks, and gives the block exit code of the hook (`hook`).
2. **Shims.** `.git-templates/hooks/<event>` is a three-line script with the marker line `# agentic-os-hook:` that runs `agentic-os hook trigger <event> "$@"`. `app git shims` copies each mapped shim into the hooks directory git uses (`core.hooksPath` when set, else the common git directory, so a worktree shares it). It refuses to overwrite a file without the marker and reports it as a conflict. `--check` reports missing or stale shims and exits 1. A mapped event with no shim file is a problem (exit 3).
3. **Hook scripts.** Files under `bin/hooks/<event>/<name>`, each with a header line `# aos-hook: output=none advisory=<true|false> default=<on|off>`:

| Script | Event | Advisory | What it does |
|---|---|---|---|
| `commit-msg/conventional` | commit-msg | false | Runs `app git lint-commit` on the message file |
| `pre-push/minimum-check` | pre-push | false | Runs `bin/modules/git/check.sh` when the project has a `components.yaml`; needs `PLUGIN_ROOT` |
| `session-start/git-shims` | session-start | true | Runs `app git shims` in a git repository; exit 3 is not an error for a session |

**Enabling.** A consuming project enables hook scripts in `.agentic-os/hooks/hooks.json`, in the `shared` list by name (`commit-msg/conventional`, `pre-push/minimum-check`, `session-start/git-shims`). The plugin's own repository does the same. Hook scripts are discovered from the plugin's `bin/hooks/`, as `plugin.yaml` declares `hooks` among its surfaces.

## Slash commands

The eight slash commands are the same thing as the `app git` commands, with a Claude Code body:

- `commands/commands.yaml` registers each one: `name`, `namespace: git`, `type: tool`, a `description` (the trigger conditions, written as "Use when ...") and an `argument-hint`.
- `commands/blueprints/tool-dispatch/<name>.md` is the body: one bash line, `bash ${BU_ROOT}/app git <name> $ARGUMENTS`, with the instruction to report its output verbatim and to add no arguments.
- The framework compiles both into the Claude Code artifacts of a project that enables the plugin: `.claude/commands/git/<name>.md`, one bash line each. The compiled files are not committed, so a fresh clone has none until the project's compile has run.

`plugin.yaml` says `adapters: [claude]`, but this plugin has no `adapters/claude/` directory. Its only adapter directory is `adapters/git/`, which maps git events. The Claude-specific pieces are the registration in `commands/`, the `session-start` hook script and the enablement in the project's `hooks.json`; the provider adapter itself is the framework's.

## Tests

### Layout and conventions

Tests live in `tests/<area>/<case>.sh`, one area per command or library:

| Area | Files | Covers |
|---|---|---|
| `git-check` | `run.sh` | `check`: green, a non-conventional commit, a failing declared check, unknown component |
| `git-cleanup` | `run.sh` | `branch-cleanup`: the dry run, the confirmation, the deletion of merged branches, the branches that are kept |
| `git-commit` | `lint.sh`, `run.sh` | `lint-commit` (no bypass for Merge or Revert, `--help`), `commit` with a stub provider |
| `git-pr` | `dry-run.sh`, `title.sh` | `pr` dry run, refusal of the main branch and of a red check; title lint |
| `git-promote` | `ff.sh`, `baseline.sh` | fast-forward, dry run and refusals; baseline mode with `--confirm` |
| `git-release` | `dry-run.sh`, `multi.sh` | the dry run end to end, several components and a single root component |
| `git-remote` | `run.sh` | the three URL forms, the github.com check, a missing remote, the identity values |
| `git-rules` | `build.sh`, `sync.sh`, `foreign.sh` | the ruleset JSON for each stage and for the main branch setting; sync against stub `docker`, `gh`, `curl`; foreign rulesets and classic protection |
| `git-shims` | `run.sh`, `push.sh` | installation, stale shims, `--check`, worktrees, `core.hooksPath`; a push in the tool image with the hook disabled |
| `git-split` | `dry-run.sh`, `apply.sh` | the dry run and the apply against bare child repositories inside the monorepo's git directory |
| `git-start` | `run.sh` | the branch in the current checkout, no upstream, carried changes, the refusals |
| `git-status` | `runs.sh` | the `runs` field of `workflow-status` with a stubbed `gh` |
| `git-version` | `range.sh` | `version_next` and `version_notes_args` on throwaway repositories |
| `token-service` | `bind.sh`, `check.sh` | the address the service listens on; `check.sh` runs it against the sandbox App: a narrowed token, the refusals, a log without tokens |

Conventions, the same in every file:

- The header has `# Purpose:` and `# Usage:` lines, and most have `# Output:`. Each file runs in `set -euo pipefail`.
- Each case prints one line: `ok   <case name>` when it holds, `FAIL <case name>` when it does not. A small helper in each file prints the line and records the failure.
- The exit code is 0 when every case holds and 1 when one fails.
- A case works in a throwaway repository under `mktemp -d` and removes it with a `trap`. Cases that push use a bare repository created in the same directory.
- Stubs replace `docker`, `gh` and `curl` on `PATH` in the rules tests (`git-rules/sync.sh`, `git-rules/foreign.sh`), and a stub `gh` replaces it in the workflow-status runs test (`git-status/runs.sh`), so those cases do not reach GitHub.

### How to run

The framework shell sets `BU_ROOT`, the `bin` directory of the framework (the directory with `lib/core.sh`). Set it yourself when you run a file directly:

```bash
export BU_ROOT=/path/to/agentic-os/bin
bash tests/git-check/run.sh
bash tests/git-remote/run.sh
```

Run every file of the area you changed. Run a whole directory with a loop:

```bash
for t in tests/*/*.sh; do bash "$t" || echo "FAILED: $t"; done
```

### What each file needs

The classification below comes from reading the code of each file and the modules it calls. The files were not executed for this manual.

| Needs | Files |
|---|---|
| Host tools only (git, jq, bash) | `git-remote/run.sh`, `git-shims/run.sh`, `git-rules/build.sh` |
| Host tools and the plugin's `node_modules` (commitlint, shellcheck): run `npm install` in the plugin root first | `git-check/run.sh`, `git-commit/lint.sh`, `git-pr/title.sh`, `git-pr/dry-run.sh` |
| Docker and the tool image (the module calls `tool_run` or `tool_image_ensure`) | `git-commit/run.sh`, `git-promote/ff.sh`, `git-promote/baseline.sh`, `git-release/dry-run.sh`, `git-release/multi.sh`, `git-shims/push.sh`, `git-split/dry-run.sh`, `git-split/apply.sh`, `git-start/run.sh`, `git-status/runs.sh`, `git-version/range.sh` |
| Docker stubbed on `PATH`, no real Docker | `git-rules/sync.sh`, `git-rules/foreign.sh` |
| Docker Compose, the sandbox GitHub App and its private key file (`APP_KEY_PATH`), network | `token-service/check.sh` |

The `token-service` case needs the key path of the sandbox App in the environment, under the variable name the test documents. Do not print or copy that value.

## CI of the plugin

The plugin repository runs one workflow, `.github/workflows/status-checks.yml`, the same file a consuming project receives:

- Trigger: `pull_request` with the types `opened`, `edited`, `synchronize` and `reopened`, on any branch.
- One job, `check`, which is the context the production rulesets require.
- Steps:
  1. Commit lint of the pull request commits with `wagoid/commitlint-github-action` and `commitlint.config.mjs`.
  2. Title lint: installs `@commitlint/cli` and `@commitlint/config-conventional` (major 21) into a temporary prefix and lints the pull request title.
  3. Declared checks: reads `.components[].checks[]` of `components.yaml` with `yq` and runs each with `bash -c`. The plugin declares one component, `git-workflow`, with a single check: `shellcheck` over `bin/lib/*.sh`, `bin/modules/*/*.sh`, `bin/hooks/*/*` and `tests/*/*.sh`, using the `shellcheck` of `node_modules/.bin`.

The CI does not run `tests/`, does not build the tool image and does not run biome, although `biome.json` is present. A change to a test or a library is checked for shell correctness only; behaviour is checked by running the tests locally.

## Adding a command

1. **Module.** Create `bin/modules/git/<name>.sh` in the shape of its neighbours: a header comment, `set -euo pipefail`, the source lines (`core.sh`, `cli.sh`, `git.sh`, then the plugin libraries from `PLUGIN_LIB`), `cli_set_spec`, the flags and options, `main`, `main "$@"`. Use `die_with` with the codes of the table above. Put every git, gh, git-cliff and splitsh-lite call that touches the remote or writes through `tool_run ... </dev/null`.
2. **Remote writes.** If the command writes as the App, call `token_fetch "<owner/name>" <set>` before the first write and `token_drop` before every return. Add the set to `bin/config/token-service.json` if none fits.
3. **Registry.** Add an entry to `bin/modules/git/module.yaml` with `name`, `description`, `requires`, `when`, `examples` and `arguments`. A command with a different entry script names it with `script:`, as `token-service` does.
4. **Slash command (optional).** Add the entry to `commands/commands.yaml` and the one-line body to `commands/blueprints/tool-dispatch/<name>.md`.
5. **Tests.** Add `tests/git-<name>/<case>.sh` in the conventions above, and one case per behaviour.
6. **Lint.** Nothing to edit: the CI check globs `bin/modules/*/*.sh` and `tests/*/*.sh`. Run shellcheck locally with the same command as the CI.
7. **Documentation.** Add the command to [Command reference](command-reference.md) and, when it changes the daily path, to [Daily loop](daily-loop.md).

## Adding a configuration option

Choose the kind of setting first:

| Kind | Where it is read | Where it is declared |
|---|---|---|
| Workflow setting for a project (branch names, stage, App ID, worktree directory) | Environment: `GIT_WORKFLOW_*`, read directly, with a default in the code. The framework loads the project's `.env` at bootstrap; the environment wins. | Document in [Configuration](git-workflow-configuration.md) |
| Plugin setting with a default, overridable per project | `${PLUGIN_EDOTZ_GIT_WORKFLOW_<NAME>:-<default>}`, as `branch-cleanup.sh` reads `PLUGIN_EDOTZ_GIT_WORKFLOW_STALE_DAYS` | A key in `bin/config/env.defaults`. Every key starts with `PLUGIN_EDOTZ_GIT_WORKFLOW_` and must not redefine a framework key. |
| Tool version or checksum | `.env.defaults` (pins) | The key in `.env.defaults`, the name in `TOOL_PIN_KEYS` in `bin/lib/tool.sh`, the `ARG` in `.docker/Dockerfile`, the `args` entry in `docker-compose.yaml` |
| Ruleset | `bin/config/rulesets.yaml` | Edit the entry; `app git rules-sync --dry-run` shows the change |
| Token permission set | `bin/config/token-service.json` | The set; the modules name it in `token_fetch` |
| Component field | `components.yaml` | In `bin/lib/component.sh`: `_COMPONENT_FIELDS` (the fields `component_field` accepts), the `known` list and the rules of `_COMPONENT_PROGRAM`, and `normalize` for the default |

A new pin key must be added to `TOOL_PIN_KEYS`. The image hash covers exactly those keys and the Dockerfile; a key left out of the list does not change the tag when it changes.

## Known gaps

Found while reading the code for this manual. Each one is a fact about the code today, not a plan.

1. **`plugin.yaml` names the `claude` adapter** without an `adapters/claude/` directory in this plugin (see [Slash commands](#slash-commands)).
2. **`branch-cleanup` still protects `release-please--*` and `backport/*`.** Both names belong to the retired old approach; the protection does no harm, and the patterns can go when no repository holds such a branch any more.
3. **`worktree --start` accepts an existing branch.** Unlike `start`, it checks the existing branch out in the new worktree instead of refusing it.
4. **The `ide` domain** has no manual in this set. Its three scripts are described above only.
