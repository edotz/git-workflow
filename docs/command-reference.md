# Command reference

Every `app git` command of the plugin, and the eight git slash commands of Claude Code. Run a command in a consuming project as `bash app git <command>`. `bash app git <command> --help` prints its options.

The tables list the options each command reads. The common flags that `--help` prints for every command (`--verbose`, `--debug`, `--json`, `--version`) are not repeated here.

The process behind release, promote and split is in [release-and-promote.md](release-and-promote.md) and [monorepo-and-split.md](monorepo-and-split.md). The daily loop is in [daily-loop.md](daily-loop.md).

## Conventions

### Exit codes

From `bash app lib exit-codes`. Each command section lists the codes it returns.

| Code | Name | Meaning |
|---|---|---|
| 0 | OK | Success. |
| 1 | FAILURE | Runtime failure, or a check that is red. |
| 2 | USAGE | Wrong arguments or an unknown mode. Also the code of a hook that blocks. |
| 3 | CONFIG | Configuration or validation failure. |
| 4 | NOT_FOUND | A required file, command, component or remote is missing. |

### Settings

Settings come from the environment. The `.env` file of the project root is loaded at start, and a variable already set in the environment wins over it. Only the names are listed here. Values belong in the project's configuration, not in this document.

| Variable | Read by | Meaning | Default |
|---|---|---|---|
| `GIT_WORKFLOW_MAIN_BRANCH` | start, pr, worktree, branch-cleanup, workflow-setup, workflow-status, release, promote, split | Main branch | `master` |
| `GIT_WORKFLOW_RELEASE_BRANCH` | promote, rules-sync, workflow-setup, workflow-status, branch-cleanup | Release branch | `master` |
| `GIT_WORKFLOW_LEGACY_BRANCHES` | rules-sync | Comma separated patterns of legacy branches | unset |
| `GIT_WORKFLOW_STAGE` | rules-sync | `development` or `production` | `development` |
| `GIT_WORKFLOW_APP_ID` | rules-sync `--apply` | Numeric id of the GitHub App | required for apply |
| `GIT_WORKFLOW_WORKTREE_DIR` | start, worktree | Absolute base directory of worktrees | `$HOME/worktrees` |
| `TOKEN_SERVICE_URL` | release, promote, split, rules-sync | URL of the token service | `http://127.0.0.1:<port>` |
| `TOKEN_SERVICE_PORT` | release, promote, split, rules-sync, token-service | Port of the token service | `8790` |
| `TOKEN_SERVICE_APP_ID` | token-service | Id of the App | required |
| `TOKEN_SERVICE_KEY_PATH` | token-service | Path of the App key file | required |
| `TOKEN_SERVICE_ORG` | token-service | Organisation the service issues tokens for | from `bin/config/token-service.json` |
| `PLUGIN_EDOTZ_GIT_WORKFLOW_STALE_DAYS` | branch-cleanup | Age in days after which an unmerged branch is stale | `30` |
| `PACKAGE_FILE` | workflow-status | File that holds the version | `package.json` |
| `CLAUDE_BIN` | commit | Optional path of the Claude CLI that drafts messages | the `claude` on `PATH` |

Credentials are not environment settings of this table. `pr`, `split` (dry run) and `branch-cleanup` use the developer's gh login (`gh auth token`). `release`, `promote`, `split` (apply) and `rules-sync` (apply) take a short-lived installation token of the App from the token service. See [github-app-and-token-service.md](github-app-and-token-service.md).

## Daily loop commands

### start

Creates the branch `<type>/<name>` and its worktree from the main branch, and prints the worktree path. The branch name is the type and the name joined by `/`; the path replaces `/` with `-`.

```text
bash app git start <type> <name>
```

| Argument | Required | Meaning |
|---|---|---|
| `type` | yes | One of `feat fix docs style refactor perf test build ci chore`. |
| `name` | yes | Lower case letters and digits, with single hyphens. |

Reads `GIT_WORKFLOW_MAIN_BRANCH` and `GIT_WORKFLOW_WORKTREE_DIR`. Needs Docker.

Exit codes: 0, 1 (branch exists locally or on origin, worktree exists, local main differs from `origin/<main>`, git failure), 2 (usage, unknown type, invalid name), 3 (worktree directory not absolute), 4 (Docker missing).

```bash
bash app git start feat add-login
```

Expected output: one line, for example `/home/you/worktrees/web/feat-add-login`.

It never fetches, never reuses an existing branch, never pushes, and never removes a worktree.

### commit

Stages the named paths and commits them with a conventional message. Without `--message` the Claude CLI drafts the message from the staged diff of those paths. The message is linted with commitlint before the commit, and the commit asks for confirmation unless `--yes` is given together with `--message`.

```text
bash app git commit [--message <text>] [--yes] <paths>...
```

| Option | Meaning |
|---|---|
| `<paths>` | Files or directories to stage and commit. Required. |
| `-m, --message <text>` | The message. No draft is made. |
| `--yes` | Skip the confirmation. Only together with `--message`. |

Reads the git identity (`user.name`, `user.email`) and `CLAUDE_BIN`, optionally. Needs Docker. The confirmation reads standard input: `y` or `yes` commits, anything else cancels.

Exit codes: 0, 1 (nothing to commit in the paths, not confirmed, the message is empty, git refused the commit), 2 (no paths, no provider and no `--message`), 3 (lint refused the message, git identity not set), 4 (Docker missing).

```bash
bash app git commit --message 'fix(login): keep the session' --yes src/login.js
```

Expected output: the header `commit message`, the message, and a line `commit` with the short hash.

It never pushes, never commits a path it was not given, never amends, and never runs the repository hooks for its own commit. Files that were staged before the command stay staged.

### check

Runs the minimum check: the commit lint of the commits since the latest tag of each component, and the commands declared in its `checks`. Writes nothing and fetches nothing.

```text
bash app git check [component]
```

| Argument | Meaning |
|---|---|
| `component` | Name of one component of `components.yaml`. Without it, every component is checked. |

Reads `components.yaml` and the commit history. Runs the declared commands on the host, from the repository root. Needs no Docker.

Exit codes: 0 (every component ok), 1 (one or more components red), 3 (`components.yaml` not valid), 4 (the named component is not declared).

```bash
bash app git check
```

Expected output, one line per component:

```text
web: ok
api: failed
```

It never writes to the repository, never uses a token, and never pushes. Without a tag, the commit lint covers every commit of `HEAD`.

### pr

Pushes the current branch and opens the pull request as the developer. The title is the subject of the only commit of the branch, or the branch name made readable when there are several commits. The body lists the commit subjects, oldest first.

```text
bash app git pr [--dry-run] [--draft]
```

| Option | Meaning |
|---|---|
| `-n, --dry-run` | Print the branch, the title and the body. Change nothing. |
| `-d, --draft` | Open the pull request as a draft. |

Reads `GIT_WORKFLOW_MAIN_BRANCH`. The apply takes the developer's token from `gh auth token` and does not read `GH_TOKEN` from the environment. The dry run needs no login and no Docker; it needs commitlint in the plugin root. The apply needs Docker and the gh login.

Exit codes: 0, 1 (current branch is the main branch, detached `HEAD`, the minimum check is red, no commit the main branch lacks), 3 (title refused by commitlint, no developer login), 4 (no remote `origin`, git cannot list the commits, gh or Docker missing).

```bash
bash app git pr --dry-run
bash app git pr --draft
```

Expected output of the dry run: the header `pull request`, the branch, the title, and the body lines `- <subject>`. Expected output of the apply: a line `push` with the branch, and a line `pull request` with the URL.

It never pushes or opens a pull request while the minimum check is red, never rewrites the title, and never uses the App token. The title is checked with the length reserve described in [daily-loop.md](daily-loop.md#title).

### workflow-status

Reports the state of the branch and of the components as JSON.

```text
bash app git workflow-status
```

Reads `GIT_WORKFLOW_MAIN_BRANCH`, `GIT_WORKFLOW_RELEASE_BRANCH` and `PACKAGE_FILE`. Needs Docker, because git runs in the tool image. The `runs` key needs a gh login and a network; without them it is an empty array and the command still succeeds.

Exit codes: 0, 1 (a git query failed).

Output keys: `current_branch`, `current_version`, `sync_status` (`ahead_of_release`, `behind_release`), `working_tree`, `unreleased_commits` (`feat`, `fix`, `breaking`, `details` up to 50 commits), `components` (`name`, `latest_release`, `commits_since_release`, `release_branch` as `on`, `behind` or `absent`), `runs`.

It never writes and never pushes.

### branch-cleanup

Groups the local and remote branches as `merged`, `stale` or `active`. A squash-merged branch counts as merged. Protected names (the main and release branches, `main`, `master`, `develop`, `development`, `staging`, `production`) are skipped.

```text
bash app git branch-cleanup [--dry-run] [--force] [--local-only | --remote-only]
```

| Option | Meaning |
|---|---|
| `-d, --dry-run` | Preview. Same report, then exit. |
| `-f, --force` | Skip the confirmation prompt. |
| `-l, --local-only` | Analyse local branches only. |
| `-r, --remote-only` | Analyse remote branches only. |

Reads `GIT_WORKFLOW_MAIN_BRANCH`, `GIT_WORKFLOW_RELEASE_BRANCH`, `PLUGIN_EDOTZ_GIT_WORKFLOW_STALE_DAYS`, and the gh login (optional, for the merged pull request lookup). Runs `git fetch --prune origin` first.

Exit codes: 0, 1 (not a git repository).

```bash
bash app git branch-cleanup --dry-run
```

Expected output: lines `merged: feat/add-login`, `stale: old/thing`, `active: ...`, with the `origin/` prefix for remote branches, then the line `Use --dry-run to preview, --force to skip confirmation`. Without a terminal and without `--force` it prints `Not interactive - use --force to skip the confirmation` and exits 0.

It never deletes a local or a remote branch, not even with `--force`. With `--force` it prints a JSON report of the three groups after the confirmation step. Removing branches is done with git; see [daily-loop.md](daily-loop.md#6-after-the-merge).

### worktree

Lists worktrees, prunes stale references, or creates a worktree for a new branch.

```text
bash app git worktree [--list | --prune | --start <branch>]
```

| Option | Meaning |
|---|---|
| `-l, --list` | List the active worktrees. The default. |
| `-p, --prune` | Run `git worktree prune`. |
| `-s, --start <branch>` | Create the branch and its worktree from the main branch, and print the path. |

Reads `GIT_WORKFLOW_WORKTREE_DIR` and `GIT_WORKFLOW_MAIN_BRANCH`. Needs no Docker for the listing.

Exit codes: 0, 1 (worktree creation failed, the worktree exists), 3 (`GIT_WORKFLOW_WORKTREE_DIR` not absolute).

```bash
bash app git worktree --list
```

Expected output: the line `Active worktrees:`, then one line per worktree as `<branch> → <path>`.

It never removes a worktree directory or a branch. Unlike `start`, `--start` does not refuse a branch that already exists: it checks that branch out in the new worktree. Use `start` to create work branches.

### lint-commit

Validates a commit message file against `commitlint.config.mjs`. The hooks call it, and so do `commit` and `pr`.

```text
bash app git lint-commit <commit-msg-file>
```

| Argument | Meaning |
|---|---|
| `commit-msg-file` | File that holds the message. Required. |

Needs commitlint in the plugin root (`npm install`). Needs no Docker.

Exit codes: 0 (accepted), 1 (file not found, commitlint not installed, or commitlint refused the message, with commitlint's own reasons), 2 (no file argument).

```bash
printf 'added stuff\n' > msg.txt
bash app git lint-commit msg.txt
```

Expected output: commitlint's report, which includes `type may not be empty`, and a non-zero exit.

It never edits the file.

### shims

Installs the git hook shims of the plugin into the hooks directory that git uses, and reports what is missing or stale.

```text
bash app git shims [--check]
```

| Option | Meaning |
|---|---|
| `-c, --check` | Report only. Exit 1 when a shim is missing or stale. |

Reads no setting. The hooks directory is `core.hooksPath` when set, else the common git directory, so a worktree shares the shims of its clone. A hook file that is not an agentic-os shim is never overwritten.

Exit codes: 0 (every shim is in place), 1 (`--check` found a shim missing or stale, or a write failed), 3 (a conflict with a foreign hook file, a mapped hook without a shim file, or no mapped hook), 4 (not inside a repository, or the hook mapping is missing).

```bash
bash app git shims
```

Expected output, one line per hook: `commit-msg: installed in <hooks directory>` on the first run, and `commit-msg: current` on the next.

It never overwrites a hook it does not own. See [daily-loop.md](daily-loop.md#hooks-that-guard-the-loop).

## Release commands

These commands are described at reference level. The process is in [release-and-promote.md](release-and-promote.md) and [monorepo-and-split.md](monorepo-and-split.md).

### release

Releases every component whose commits since its latest stable tag make a release. Dry run prints the plan; apply makes the release commit `chore(<component>): release <tag>`, the tag, the push, and the GitHub Release.

```text
bash app git release (--dry-run | --apply) [--draft] [--pre <channel>]
```

| Option | Meaning |
|---|---|
| `-n, --dry-run` | Per component: the next version, the tag, the files and the notes. Change nothing. |
| `-a, --apply` | Make the release commit, the tag, push them, and create the GitHub Release. |
| `-d, --draft` | Leave the GitHub Release unpublished. |
| `-p, --pre <channel>` | Make a pre-release of this channel, lower case letters, for example `rc`. |

Reads `GIT_WORKFLOW_MAIN_BRANCH`, `TOKEN_SERVICE_URL`, `TOKEN_SERVICE_PORT`. Needs Docker. Apply needs the token service running and the git identity set.

Exit codes: 0, 1 (runtime failure), 2 (neither or both of `--dry-run` and `--apply`), 3 (git identity not set for apply).

```bash
bash app git release --dry-run
bash app git release --apply --pre rc
```

Expected output of the dry run: a header `release <component>` per component with the lines `version`, `tag` and `files`, then the notes. Apply does the steps listed above and leaves master unchanged apart from the release commit.

It never releases a component that has no release-making commit since its tag, and the dry run never tags or pushes.

### promote

Moves the release branch to the commit of a release tag. It never moves the branch to the head of `master`. A fast-forward needs no confirmation. When the release branch is not an ancestor of the tag commit, the command is in baseline mode and needs `--confirm`.

```text
bash app git promote <tag> (--dry-run | --apply) [--confirm <owner/repo>]
```

| Argument or option | Meaning |
|---|---|
| `tag` | Release tag. Required. Its commit must be the release commit `chore(<component>): release <tag>`. |
| `-n, --dry-run` | Print the commit the release branch would move to. Change nothing. |
| `-a, --apply` | Push the commit of the tag to the release branch, as the App. |
| `-c, --confirm <owner/repo>` | Needed to replace a release branch that is not an ancestor of the tag. The old head is tagged `legacy/pre-promote`. |

Reads `GIT_WORKFLOW_MAIN_BRANCH`, `GIT_WORKFLOW_RELEASE_BRANCH`, `TOKEN_SERVICE_URL`, `TOKEN_SERVICE_PORT`.

Exit codes: 0, 1 (runtime failure), 2 (no tag, neither or both flags, a diverged branch without `--confirm`, `--confirm` names another repository), 4 (the tag does not exist).

```bash
bash app git promote v1.2.0 --dry-run
bash app git promote v1.2.0 --apply
```

The dry run names the commit and, when the branch diverged, the divergence. Apply pushes the fast-forward. The process is in [release-and-promote.md](release-and-promote.md).

It never moves the release branch to the head of `master`, and never replaces a diverged branch without `--confirm`.

### split

Shows, or pushes, the split of one component into its child repository. Dry run prints the split head, its ancestry to the child head, and the tree difference. Apply pushes the split head to the child's main branch, and the component tags as `vX.Y.Z`. One child per apply.

```text
bash app git split [<component>] --dry-run
bash app git split <component> --apply [--confirm <owner/repo>]
```

| Argument or option | Meaning |
|---|---|
| `component` | The component. The dry run takes every split component without it. The apply needs exactly one. |
| `-n, --dry-run` | Print the split head, the ancestry and the tree difference. Change nothing. |
| `-a, --apply` | Push the split head and the component tags to the child, with the installation token of the App. |
| `-c, --confirm <owner/repo>` | Needed to replace a child that does not descend from the split. Its old head is kept as `legacy/pre-split`. |

Reads `GIT_WORKFLOW_MAIN_BRANCH`, `TOKEN_SERVICE_URL`, `TOKEN_SERVICE_PORT`. The dry run reads the child with the developer's gh login.

Exit codes: 0, 1 (runtime failure), 2 (the component has `split: no`, `--confirm` names another child, a child that does not descend without `--confirm`, neither or both flags, apply without exactly one component), 3 (the child's default branch differs from `GIT_WORKFLOW_MAIN_BRANCH`), 4 (component not declared).

```bash
bash app git split web --dry-run
bash app git split web --apply
```

It never moves a child tag that exists at another commit, which is skipped with a warning, and never replaces a child without `--confirm`.

### rules-sync

Creates or updates the branch rulesets of the repository from `bin/config/rulesets.yaml`, as the App.

```text
bash app git rules-sync [--dry-run | --apply] [--stage <development|production>]
```

| Option | Meaning |
|---|---|
| `-n, --dry-run` | Default. Per ruleset: create, update, unchanged or skipped. Change nothing. |
| `-a, --apply` | Create or update the rulesets. Needs `GIT_WORKFLOW_APP_ID`. |
| `-s, --stage <stage>` | `development` or `production`. Default `GIT_WORKFLOW_STAGE`, else `development`. |

Reads `GIT_WORKFLOW_STAGE`, `GIT_WORKFLOW_APP_ID`, `GIT_WORKFLOW_RELEASE_BRANCH`, `GIT_WORKFLOW_LEGACY_BRANCHES`, `TOKEN_SERVICE_URL`, `TOKEN_SERVICE_PORT`. Needs Docker and `curl`.

Exit codes: 0, 1 (runtime failure), 2 (both `--dry-run` and `--apply`, an unknown ruleset or stage), 3 (`GIT_WORKFLOW_APP_ID` missing or not numeric on apply, `rulesets.yaml` not valid).

```bash
bash app git rules-sync --dry-run --stage production
```

Expected output: one line per ruleset with its action.

It never touches or deletes a ruleset that the file does not name. A ruleset or a classic branch protection that still covers a managed branch is named in the output and left alone. See [rulesets-and-ci.md](rulesets-and-ci.md).

## Setup commands

### workflow-setup

Validates `GIT_WORKFLOW_MAIN_BRANCH` and `GIT_WORKFLOW_RELEASE_BRANCH` and prints them. The `apply`, `check` and `init` forms are removed; rulesets are applied with `rules-sync`.

```text
bash app git workflow-setup [validate]
```

Reads `GIT_WORKFLOW_MAIN_BRANCH` and `GIT_WORKFLOW_RELEASE_BRANCH`, both defaulting to `master`.

Exit codes: 0, 2 (unknown option or command, or a removed form), 3 (a branch setting holds whitespace).

```bash
bash app git workflow-setup
```

Expected output:

```text
GIT_WORKFLOW_MAIN_BRANCH    : master
GIT_WORKFLOW_RELEASE_BRANCH : master
```

It never writes a setting.

### token-service

Runs the token service: a local server that issues one-hour installation tokens of the GitHub App, narrowed to one repository and one permission set, to the members of the organisation. It runs as a long-lived process. It takes its settings from the environment only; `--help` is not supported.

```text
TOKEN_SERVICE_APP_ID=<app-id> TOKEN_SERVICE_KEY_PATH=<path-to-key> bash app git token-service
```

| Variable | Meaning |
|---|---|
| `TOKEN_SERVICE_APP_ID` | Id of the App. Required. |
| `TOKEN_SERVICE_KEY_PATH` | Path of the App's private key file. Required. The key is read from this path and is never copied into an image. |
| `TOKEN_SERVICE_PORT` | Port to listen on. Default `8790`. |
| `TOKEN_SERVICE_ORG` | Organisation. Default from `bin/config/token-service.json`. |

Exit codes: 1 (a required variable is missing, or the service stops with an error).

Without the required variables it prints `TOKEN_SERVICE_APP_ID and TOKEN_SERVICE_KEY_PATH are required` and exits 1.

It never prints or stores the key. The permission sets are in `bin/config/token-service.json`; see [github-app-and-token-service.md](github-app-and-token-service.md).

## Slash commands

The eight git slash commands are defined in `commands/commands.yaml` and dispatch with the same blueprint: each runs `bash app git <name> $ARGUMENTS`, reports the output unchanged, and adds nothing. Their options, environment variables and exit codes are those of the `app git` command they run, listed above. The arguments are passed as typed after the slash command.

| Slash command | Runs | Argument hint |
|---|---|---|
| `/git:start` | `app git start` | `<type> <name>` |
| `/git:commit` | `app git commit` | `<paths> [--message <text>] [--yes]` |
| `/git:check` | `app git check` | `[component]` |
| `/git:pr` | `app git pr` | `[--dry-run] [--draft]` |
| `/git:release` | `app git release` | `[--dry-run\|--apply] [--draft] [--pre <channel>]` |
| `/git:promote` | `app git promote` | `<tag> [--dry-run\|--apply]` |
| `/git:rules-sync` | `app git rules-sync` | `[--dry-run\|--apply] [--stage <development\|production>]` |
| `/git:split` | `app git split` | `[component] --dry-run` or `<component> --apply [--confirm <owner/repo>]` |

Commands run in the directory of the Claude Code session. Start the session in the worktree that `/git:start` printed.

Each slash command takes the options, settings and exit codes of the `app git` command in the table above; its output is the output of that command.

| Slash command | Example | Never |
|---|---|---|
| `/git:start` | `/git:start feat add-login` | Checks out an existing branch. Leave the printed worktree. |
| `/git:commit` | `/git:commit src/login.js --message "feat(login): keep the session after a reload" --yes` | Pushes, or commits paths that were not named. Without `--message` and `--yes` the confirmation gets no answer, and the commit is declined with `commit: not confirmed, nothing was committed`. |
| `/git:check` | `/git:check web` | Writes to the repository. |
| `/git:pr` | `/git:pr --dry-run`, `/git:pr --draft` | Uses `gh pr create --fill`. Pushes while the minimum check is red. |
| `/git:release` | `/git:release --dry-run` | Publishes or tags in a dry run. |
| `/git:promote` | `/git:promote v1.2.0 --dry-run` | Moves the release branch to the head of `master`. |
| `/git:rules-sync` | `/git:rules-sync --dry-run --stage production` | Touches a ruleset that `rulesets.yaml` does not name. |
| `/git:split` | `/git:split web --dry-run` | Replaces a child without `--confirm`, or splits more than one child per apply. |
