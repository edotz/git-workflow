# Configuration

This manual lists every file and setting that the plugin reads: the component declaration `components.yaml`, the environment variables and the `.env` files, the stages, the commit message rules, the changelog filter, and the settings of the token service. The process that uses the rulesets is in [Rulesets and CI](rulesets-and-ci.md). The App and the token service are described in [GitHub App and token service](github-app-and-token-service.md).

Commands are written as `app git <command>` in prose and as `bash ${BU_ROOT}/app git <command>` in examples, where `${BU_ROOT}/app` is the entry point of the agentic-os framework.

## Where each setting lives

| Setting | File | Read by | Who changes it |
|---|---|---|---|
| Components, paths, checks, versions, split | `components.yaml` in the repository root | `check`, `pr`, `release`, `split` and the pre-push hook | the repository's developers |
| Branch names, stage, App ID, legacy patterns, token service address | `.env` in the repository root (or the process environment) | the git commands | each developer or the CI operator |
| Stale days, VS Code profile directory | plugin `bin/config/env.defaults` | branch cleanup, VS Code profile module | the plugin maintainers |
| Image pins of the tool image | plugin root `.env.defaults` | Docker Compose, the tool image build | the plugin maintainers |
| Commit types and limits | plugin `commitlint.config.mjs` (and a copy in each repository for CI) | commit lint, pull request title lint | the plugin maintainers |
| Changelog and version bump filter | plugin `bin/config/cliff.toml` | version bump and release notes | the plugin maintainers |
| Permission sets of the token service | plugin `bin/config/token-service.json` | the token service | the plugin maintainers |
| Rulesets | plugin `bin/config/rulesets.yaml` | `rules-sync` | the plugin maintainers |

## components.yaml

`components.yaml` sits in the repository root. Its only top-level key is `components`, a list with at least one entry. Any other top-level key is refused. The file is read by `bin/lib/component.sh`, which checks every rule below before a command runs and prints every violated rule with its component name. A declaration that breaks a rule stops the command with exit code 3 and changes nothing.

### Fields

| Field | Type | Default | Validation | Meaning |
|---|---|---|---|---|
| `name` | string | required | lower case letters, digits and hyphens, starting with a letter; unique in the file | Name of the component. It is part of the tag of the component when there are two or more components. |
| `paths` | list of strings | required unless `workspace` is given | non-empty list; relative to the repository root; no leading `/`, no `..`; `.` only when the file has one component | Directories that belong to the component. Every commit that touches one of them counts for the component. |
| `workspace` | string | required unless `paths` is given | name of a package of a pnpm workspace; needs pnpm 10 on the host | The package and every workspace package it depends on, directly or through others. The directories come from `pnpm list` on each run and are never stored. Not allowed together with `paths`. |
| `version` | `yes` or `none` | `yes` | any other value is refused | `none` gives the component no version and no tag. |
| `version_files` | list of strings | empty | list of file names; relative to the repository root | Files that receive the version of a release. Refused with `version: none` when not empty. See the writers below. |
| `checks` | list of strings | empty | list of shell commands | Commands run from the repository root. A non-zero exit fails the check. Run by `app git check`, the pre-push hook, `app git pr`, the release gate and the `check` job of CI. |
| `split` | `yes` or `no` | `no` | `yes` needs `version: yes`, `owner`, `repo`, and a file with more than one component | `yes` sends the component to a child repository. See [Monorepo and split](monorepo-and-split.md). |
| `owner` | string | required with `split: yes` | non-empty string; refused without `split: yes` | Owner of the child repository. |
| `repo` | string | required with `split: yes` | non-empty string; refused without `split: yes` | Name of the child repository. |
| `host` | string | `github.com` | non-empty string; refused without `split: yes` | Host of the child repository. |

Any other field is refused with `unknown field`. There is no `kind` field and no pre-release field: pre-releases are chosen when the release command runs, with `--pre <channel>` (see [Release and promote](release-and-promote.md)).

### Writers of version_files

The release writes the version into each file of `version_files` and reads every file back. The writer is chosen by the file name:

| File name | What is written | Rule |
|---|---|---|
| `package.json` | the `version` key | any package.json |
| `composer.json` | the `version` key | only when the file already has a `version` key; otherwise the release refuses, because Composer reads the tag |
| `ext_emconf.php` | the one `'version' =>` line | exactly one such line; only a plain `X.Y.Z` version, so this file cannot take a pre-release |
| any other name | nothing | a configuration error when the version is written |

The lockfile of a workspace is never listed and never changed.

### Examples

A single repository with one component and a version (the file of a single package):

```yaml
components:
  - name: object
    paths: ["."]
    version_files: [package.json]
```

A single component without a version, with its own checks (this is the declaration of the plugin repository itself):

```yaml
components:
  - name: git-workflow
    paths: ["."]
    version: none
    checks:
      - 'PATH="$PWD/node_modules/.bin:$PATH" shellcheck bin/lib/*.sh bin/modules/*/*.sh bin/hooks/*/* tests/*/*.sh'
```

A monorepo with a Node workspace package, a package that is split to its own repository, and a component without a version. The owner and repository names are placeholders:

```yaml
components:
  - name: web
    workspace: "@acme/web"
    version_files: [apps/web/package.json]
    checks: ["pnpm run lint"]
  - name: api
    paths: [apps/api]
    version_files: [apps/api/package.json]
    split: yes
    owner: acme
    repo: api
  - name: infra
    paths: [infra]
    version: none
    checks: ["terraform fmt -check", "terraform validate"]
```

A TYPO3 extension in its own repository. The version lives in `ext_emconf.php`; `composer.json` is left out because a TYPO3 extension normally carries no `version` key there:

```yaml
components:
  - name: ext
    paths: ["."]
    version_files: [ext_emconf.php]
    checks: ["composer validate --strict"]
```

A Node workspace package in a repository that is not split. The version file is the package's own `package.json`:

```yaml
components:
  - name: ui
    workspace: "@acme/ui"
    version_files: [packages/ui/package.json]
```

A component whose directory is shared with another component is allowed. A commit that touches both counts for both.

## Environment variables

The git commands read their settings from the environment. The table lists every name the plugin reads. The defaults are the values used when the name is unset.

### Branch and stage settings

| Name | Default | Meaning | Read by |
|---|---|---|---|
| `GIT_WORKFLOW_MAIN_BRANCH` | `master` | The main branch: start point of branches, target of pull requests, target of release commits and of split pushes. | `start`, `pr`, `release`, `promote`, `split`, `rules-sync`, `workflow-setup`, `workflow-status`, `branch-cleanup`, `lib/worktree.sh` |
| `GIT_WORKFLOW_RELEASE_BRANCH` | unset | The release branch, for example `1.x`. `promote` treats an unset value as `master`, which means nothing to promote, so promote does nothing. `rules-sync` skips the `release` ruleset when it is unset. | `promote`, `rules-sync`, `workflow-setup`, `workflow-status` |
| `GIT_WORKFLOW_LEGACY_BRANCHES` | unset | Comma separated branch names or glob patterns of the old lines. `branch-cleanup` never deletes them, and the `legacy` ruleset covers them; without a value `rules-sync` skips that ruleset. | `rules-sync` through `bin/config/rulesets.yaml` |
| `GIT_WORKFLOW_STAGE` | `development` | Stage of the `master` ruleset: `development` or `production`. `rules-sync --stage` overrides it. Any other value is refused. | `rules-sync`, `lib/rules.sh` |
| `GIT_WORKFLOW_APP_ID` | unset | Numeric ID of the App. It becomes the bypass actor of the rulesets. Required by `rules-sync --apply`; must be digits only. | `rules-sync` |
| `GIT_WORKFLOW_WORKTREE_DIR` | `$HOME/worktrees` | Absolute directory where worktrees are created, below a folder named after the repository. A relative value is refused. | `worktree`, `lib/worktree.sh` |

### Token service settings

| Name | Default | Meaning | Read by |
|---|---|---|---|
| `TOKEN_SERVICE_URL` | `http://127.0.0.1:<TOKEN_SERVICE_PORT>` | Base URL the CLI calls for installation tokens. Set it only when the service runs elsewhere. | `lib/token.sh` (through `release`, `promote`, `split`, `rules-sync --apply`) |
| `TOKEN_SERVICE_HOST` | `127.0.0.1` | Address the token service listens on. The container sets `0.0.0.0` and publishes its port on the loopback address only. | `token-service.mjs`, `docker-compose.yaml` |
| `TOKEN_SERVICE_PORT` | `8790` | Port of the default URL. The compose file publishes the container on this port, on the loopback address only. | `lib/token.sh`, `docker-compose.yaml`, `token-service.mjs` |
| `TOKEN_SERVICE_APP_ID` | empty | Numeric ID of the App the service signs for. Required by the service; the service stops without it. | `token-service.mjs`, `docker-compose.yaml` |
| `TOKEN_SERVICE_KEY_PATH` | `/run/secrets/app-key.pem` inside the container | Path the service reads the App's private key from. Required by the service; set by compose inside the container. Its value on a host is never recorded in a repository or a document. | `token-service.mjs`, `docker-compose.yaml` |
| `TOKEN_SERVICE_KEY_FILE` | `/dev/null` | Host file that compose mounts read-only as the key. Compose reads it; it is not a setting of the CLI. | `docker-compose.yaml` |
| `TOKEN_SERVICE_ORG` | `org` of `bin/config/token-service.json` (`edotz`) | Organisation the service serves. A repository outside it is refused. | `token-service.mjs` |
| `TOKEN_SERVICE_UID`, `TOKEN_SERVICE_GID` | `1000` | User and group the container runs as. | `docker-compose.yaml` |

The CLI timeout of the token request is a constant, 20 seconds, in `bin/lib/token.sh`. It is not a setting.

### Plugin settings (bin/config/env.defaults)

| Name | Default | Meaning | Read by |
|---|---|---|---|
| `PLUGIN_EDOTZ_GIT_WORKFLOW_STALE_DAYS` | `30` | Days after which a branch counts as stale in `branch-cleanup`. | `branch-cleanup` |
| `PLUGIN_EDOTZ_GIT_WORKFLOW_VSCODE_PROFILES_DIR` | empty, which means `.vscode/profiles` of the plugin | Directory with the VS Code profile files. | `vscode-profile` module |

Every key of that file starts with `PLUGIN_EDOTZ_GIT_WORKFLOW_`.

### Image pins (.env.defaults in the plugin root)

These names are read by Docker Compose and by the Dockerfile, not by the git commands. They pin the base image by digest and the tool versions with their checksums: `IMAGE_BASE`, `IMAGE_PLATFORM`, `GIT_CLIFF_VERSION`, `GIT_CLIFF_SHA512`, `SPLITSH_VERSION`, `SPLITSH_SHA256`, `GH_VERSION`, `GH_SHA256`, `GIT_APT_VERSION`. A developer of a consuming project does not set them. The tool image is built for `linux/amd64` only, because splitsh-lite publishes no arm64 binary.

## Loading order of the .env files

A `.env` file holds one `KEY=value` per line. Do not put inline comments after a value: the shell keeps them as part of the value, and the framework's env lint reports them. The plugin's `.gitignore` ignores `*.env`, so a `.env` is never committed.

The framework loads the settings of a command in this order, highest priority first:

1. The process environment. A variable set in the shell is never overridden.
2. The `.env` of the project root (the repository where the command runs).
3. The `bin/config/env.defaults` of each plugin (the `PLUGIN_EDOTZ_GIT_WORKFLOW_*` keys).
4. The defaults of the framework.

A defaults file sets a key only when no higher layer has set it. The source is `bin/lib/bootstrap.sh` (stage `env`) and `bin/lib/env.sh` of the framework.

The tool image pins follow their own rule, in `bin/lib/tool.sh`:

1. The `.env.defaults` of the plugin root gives the pins.
2. The `.env` of the plugin root, when it exists, overrides them key by key.
3. The process environment and the `.env` of a consuming project do not change the pins.

Compose reads the same files with `--env-file .env.defaults`, followed by `--env-file .env` when that exists, as the header of `.env.defaults` says.

## Stages

The stage decides which rules the `master` ruleset carries. It is set by `GIT_WORKFLOW_STAGE` or by `rules-sync --stage`, and defaults to `development`.

| Ruleset | development | production |
|---|---|---|
| `master` | no rule; the App is the bypass actor | pull request (squash only), required status check `check`, linear history |
| `release` | same in both stages | same in both stages |
| `legacy` | same in both stages | same in both stages |

The stage changes nothing else: no command reads `GIT_WORKFLOW_STAGE` except `rules-sync` and the rules library. The rules of each ruleset are explained in [Rulesets and CI](rulesets-and-ci.md).

## commitlint.config.mjs

The file extends `@commitlint/config-conventional` and overrides these rules:

| Rule | Setting | Meaning |
|---|---|---|
| `type-enum` | level 2, always | the type must be one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore` |
| `type-case` | level 2, `lower-case` | type in lower case |
| `type-empty` | level 2, never empty | a type is required |
| `scope-case` | level 2, `lower-case` | scope in lower case |
| `subject-empty` | level 2, never empty | a subject is required |
| `subject-case` | off (0) | no case rule for the subject |
| `subject-full-stop` | level 2, never `.` | no full stop at the end of the subject |
| `subject-max-length` | level 2, 100 | the subject is at most 100 characters |

The header limit of 100 characters comes from `@commitlint/config-conventional`, which the file extends: the header is type, scope, colon and subject. A type that is not in the list is refused, including `revert` and `merge`.

The file is used in four places: `bin/modules/git/lint-commit.sh` (the commit-msg hook, `app git commit`, `app git check`, the pre-push hook and `app git pr` for the title), and the `status-checks.yml` workflow, which reads a copy of the file from the root of the consuming repository. Keep the copy identical to the plugin file.

## cliff.toml

`bin/config/cliff.toml` configures git-cliff, which computes the next version and writes the release notes. The version code sends the file to git-cliff over stdin (`bin/lib/version.sh`), because the tool image mounts only the repository.

What the file filters, and why:

- Only commits with the type `feat`, `fix` or `perf`, and breaking commits (`!` after the type or a `BREAKING CHANGE` footer), are parsed into groups. `filter_commits = true` drops every other commit. The result: `chore`, `ci`, `docs`, `test`, `style`, `refactor` and `build` commits in a component path neither make a release nor appear in the notes.
- `filter_unconventional = true` drops commits that do not follow the conventional form.
- Commits are sorted oldest first inside a section.
- The version bump uses only the commits after the latest stable tag of the component (the tag pattern accepts `X.Y.Z` only for the base version). Where the baseline tag sits does not matter.

Only these types change what a user of the component gets, so only these types bump the version and appear in the notes.

## token-service.json

`bin/config/token-service.json` holds the organisation and the permission sets. The token service reads it when it starts, and the container image copies it at build time, so a change needs a rebuild of the image. A set is a mapping from permission name to level. A request names one set; the service asks GitHub for a token with exactly those permissions.

| Set | Permissions | Used by | Notes |
|---|---|---|---|
| `contents` | `contents: write` | `release --apply`, `promote --apply` | Pushes the release commit and tag, creates the GitHub Release, moves the release branch. |
| `split` | `contents: write`, `workflows: write` | `split --apply` | Pushes the split head and the component tags to a child repository. The child repository receives workflow files with the component history, so only this set carries `workflows: write`; see [GitHub App and token service](github-app-and-token-service.md#permission-sets). |
| `administration` | `administration: write` | `rules-sync --apply` | Creates and updates rulesets. |

The `org` key is `edotz`. A set name that is not listed is refused with `permission set unknown`.

## rulesets.yaml (reference)

`bin/config/rulesets.yaml` is the data that `rules-sync` turns into GitHub ruleset bodies. The process is in [Rulesets and CI](rulesets-and-ci.md). The keys:

| Key | Meaning |
|---|---|
| `stages` | List of the stage names. Must not be empty. |
| `rulesets.<name>` | One ruleset per name: `master`, `release`, `legacy`. |
| `target`, `enforcement` | Copied to the ruleset body (`branch`, `active`). |
| `conditions.ref_name` | Branch patterns of the ruleset. |
| `include_from` | Name of an environment variable holding the comma separated branch patterns. Unset or blank is a configuration failure, and `rules-sync` skips that ruleset, unless the entry has `include_default`. |
| `include_default` | The branch patterns used when the `include_from` setting is unset or blank. |
| `extends` | Name of another entry; the fields of this entry win. |
| `bypass_actors` | The App as the bypass actor. The placeholder `APP_ID_PLACEHOLDER` is replaced by `GIT_WORKFLOW_APP_ID` before the body is sent. |
| `rules` | A list of rules, or a map from stage name to a list. |

A pattern in `include_from` without `refs/` or `~` is read as a branch name and gets the prefix `refs/heads/`. The `master` ruleset takes its pattern from `GIT_WORKFLOW_MAIN_BRANCH` and falls back to `master` through `include_default`, so it always applies.

The loader (`rules_load` in `bin/lib/rules.sh`) refuses a file that is not valid YAML with exit 3, and a file without a stage list or a ruleset map with exit 3. A missing file is exit 4. An unknown ruleset or stage name is exit 2.

## Exit codes of the configuration checks

| Code | Name | When |
|---|---|---|
| 2 | `BU_EXIT_USAGE` | a missing argument, an unknown ruleset or stage, a bad option |
| 3 | `BU_EXIT_CONFIG` | a rule of `components.yaml` is broken, a required variable is unset, a setting has the wrong form |
| 4 | `BU_EXIT_NOT_FOUND` | a file is missing, a component is not declared |

Exit codes of the other commands are in [Command reference](command-reference.md).

## Related

- [Overview](overview.md): the model of branches, components and stages.
- [Monorepo and split](monorepo-and-split.md): how components are split and tagged.
- [Release and promote](release-and-promote.md): what the version fields and `--pre` do.
- [Rulesets and CI](rulesets-and-ci.md): rulesets, `rules-sync`, the workflow and the hooks.
- [GitHub App and token service](github-app-and-token-service.md): the App and the service that reads `token-service.json`.
- [Adopting in a project](adopting-in-a-project.md): the first `components.yaml` of a project.
