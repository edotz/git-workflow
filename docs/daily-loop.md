# Daily loop

The daily loop takes one change from a clean `master` to a merged pull request. Each step is one `app git` command, and each command has a slash command in Claude Code. The same steps are listed in [The loop in Claude Code](#the-loop-in-claude-code).

The loop is strict about commit messages on purpose. A pull request is squash-merged, so its title becomes the only commit of the change on `master`. The release version is counted from the subjects of those commits. A wrong title is a wrong release note, and it can be a wrong version. Every step therefore checks the message before it leaves your machine.

## Prerequisites

- Docker is running. Git and gh run in the plugin's tool image, and `app git start`, `commit`, `pr` (apply) and `workflow-status` need it.
- `gh auth login` is done. `app git pr` pushes and opens the pull request with your own login.
- `user.name` and `user.email` are set in your git configuration. `app git commit` uses them as the author.
- The hook shims are installed in the clone. `app git shims` does this; in Claude Code the session-start hook runs it for you. See [Hooks that guard the loop](#hooks-that-guard-the-loop).
- The commitlint package is installed in the plugin root (`npm install` there). The title lint and the commit lint use it.

## The loop at a glance

| Step | Command | Result |
|---|---|---|
| 1. Start | `bash ${BU_ROOT}/app git start <type> <name>` | Branch `<type>/<name>` from the main branch, checked out; its name is printed |
| 2. Commit | `bash ${BU_ROOT}/app git commit <paths>` | One commit of the named paths, with a checked message |
| 3. Check | `bash ${BU_ROOT}/app git check [component]` | One line per component: `ok` or `failed` |
| 4. Pull request | `bash ${BU_ROOT}/app git pr [--dry-run] [--draft]` | Branch pushed, pull request opened |
| 5. Merge | GitHub, "Squash and merge" | One commit on `master` |
| 6. Cleanup | `bash ${BU_ROOT}/app git branch-cleanup` | Merged local and remote branches removed |
| Any time | `bash ${BU_ROOT}/app git workflow-status` | JSON status of the branch and the components |

## 1. Start

Run it inside the repository.

```bash
bash ${BU_ROOT}/app git start feat add-login
```

Expected output: one line, the name of the new branch, `feat/add-login`. The checkout is now on that branch. Uncommitted changes of the working tree go along, as with `git switch`; git refuses the switch when a change would be overwritten.

Rules:

- The type is one of the ten types of `commitlint.config.mjs`: `feat fix docs style refactor perf test build ci chore`.
- The name is lower case letters and digits, with single hyphens between words: `add-login`.
- The branch is `<type>/<name>`, created from the local main branch (`GIT_WORKFLOW_MAIN_BRANCH`, default `master`) and checked out in the current checkout. It has no upstream, so `git pull` on it does not pull `master`.
- Name the branch like the subject you want. A single commit gives its own subject as the pull request title. Several commits give a title built from the branch name, so `feat/add-login` becomes `feat: add login` (see [Pull request](#4-pull-request)).

`start` does not fetch. It refuses to start while the local main branch differs from `origin/<main>` (when that remote branch is known), so update master first.

| Message | Exit | Fix |
|---|---|---|
| `Unknown type 'x': one of feat fix ...` | 2 | Use one of the ten types. |
| `Invalid name 'X': lower case letters and digits, separated by single hyphens` | 2 | Rename it, for example `add-login`. |
| `Branch exists locally: feat/add-login` | 1 | `start` never reuses a branch. Pick another name, or switch to the existing branch with `git switch`. |
| `Branch exists on origin: feat/add-login` | 1 | Pick another name. `start` does not check out a remote branch. |
| `Local master is not in sync with origin/master. Run: git fetch origin && git switch master && git merge --ff-only origin/master` | 1 | Run the printed command, then start again. |
| Docker is not available | 4 | Start Docker. |

## 2. Commit

```bash
bash ${BU_ROOT}/app git commit src/login.js
```

What the command does, in order:

1. Stages the named paths with `git add -- <paths>`. Other files that are already staged stay staged and are not committed.
2. Unless `--message` is given, drafts the message from the staged diff of those paths with the Claude CLI (the provider). The draft is asked for in the form `type(scope): subject`. The diff is cut at 30000 characters.
3. Prints the message under the header `commit message` and lints it with commitlint. A refused message commits nothing and restores the index.
4. Asks `Commit with this message? [y/N]`. Only `y` or `yes` commits. Any other answer, including an empty input, cancels.
5. Commits with your git identity. Repository hooks are switched off for this commit, because the message was just linted.

Options:

| Option | Meaning |
|---|---|
| `<paths>` | Files or directories to stage and commit. Required. |
| `-m, --message <text>` | Use this message. No draft is made. |
| `--yes` | Skip the confirmation. Only together with `--message`. Without `--message` the confirmation still runs. |

With a message, and without the confirmation:

```bash
bash ${BU_ROOT}/app git commit --message 'feat(login): keep the session after a reload' --yes src/login.js
```

Expected output: the header `commit message`, the message, and a line `commit` with the short hash of the new commit.

Conventional commit rules (checked by commitlint with `commitlint.config.mjs`):

| Part | Rule |
|---|---|
| Type | One of `feat fix docs style refactor perf test build ci chore`, lower case. |
| Scope | Optional, in parentheses, lower case: `feat(login)`. |
| Breaking change | `!` before the colon, or a footer `BREAKING CHANGE: ...`. |
| Subject | After `: `. Not ending with a full stop. Case is not checked. |
| Header | `type(scope): subject`, at most 100 characters. |
| Body | Optional, after one blank line. Not checked. |

Only commits of type `feat`, `fix` and `perf`, and breaking commits, make a release of a component. Commits of `chore`, `ci`, `docs`, `test`, `style`, `refactor` and `build` in a component path do not. The rules are in [release-and-promote.md](release-and-promote.md).

| Message | Exit | Fix |
|---|---|---|
| `commit: name the paths to commit. Usage: ...` | 2 | Pass at least one path. |
| `commit: no provider is available to draft the message, give one with --message` | 2 | Install and log in to the Claude CLI, or pass `--message`. |
| `commit: nothing to commit in the paths named` | 1 | The paths have no change. Check with `git status`. |
| `commit: the message is refused by lint-commit, nothing was committed` | 3 | Read the commitlint reason above it and pass a valid `--message`. |
| `commit: the provider gave no message, give one with --message` | 1 | Pass `--message`. |
| `commit: not confirmed, nothing was committed` | 1 | Answer `y`, or pass `--message` with `--yes`. See [Slash commands](#the-loop-in-claude-code). |
| `remote: git config user.name is not set` (or `user.email`) | 3 | Set the value in your git configuration. |
| Docker is not available | 4 | Start Docker. |

A plain `git commit` in a clone with the shims runs the commit-msg hook instead, and a refused message aborts that commit. `app git commit` does not run the hook, it lints the message itself.

## 3. Check

```bash
bash ${BU_ROOT}/app git check
bash ${BU_ROOT}/app git check web
```

Without an argument the check runs for every component of `components.yaml`. With a name it runs for that component only. For each component it runs two steps, and every step runs even when an earlier one failed:

1. **Commit lint.** Every commit subject from the latest tag of the component to `HEAD` is linted with commitlint. The tag is `<name>/v<version>` when the repository has two or more components, and `v<version>` with one. The range covers all commits in it, not only the commits that touch the component's paths. Without a tag, every commit reachable from `HEAD` is linted. In a repository that never had a tag, that is the whole history, so add the baseline tag first (see [monorepo-and-split.md](monorepo-and-split.md) and [release-and-promote.md](release-and-promote.md)).
2. **Declared checks.** Each command of the `checks` field of the component runs on the host, from the repository root. Their tools must be installed on the host.

Expected output, one line per component:

```text
web: ok
api: failed
```

The output also names each failing commit (`commit lint failed: <subject>`) and each failing command (`check command failed: <command>`). When any component is red, the command exits 1 with `check: 1 component(s) red`.

| Message | Exit | Fix |
|---|---|---|
| `commit lint failed: <subject>` | 1 | Reword that commit. Use `git commit --amend` for the last commit, and an interactive rebase in your terminal for an older one. Then run the check again. |
| `check command failed: <command>` | 1 | Run the command from the repository root and fix what it reports. |
| `check: component 'x' is not declared in components.yaml` | 4 | Name a component declared in `components.yaml`. |
| `components.yaml` is not valid | 3 | Fix the file. See [git-workflow-configuration.md](git-workflow-configuration.md). |

The check reads the history and writes nothing. It is also the pre-push guard: `git push` runs it for all components first (see [Hooks](#hooks-that-guard-the-loop)).

## 4. Pull request

Start with a dry run. It changes nothing and needs no login:

```bash
bash ${BU_ROOT}/app git pr --dry-run
```

Expected output: the header `pull request`, then the branch, the title, and the body. The body lists the commit subjects of the branch, oldest first, as `- <subject>` lines. The dry run runs the minimum check and the title lint too, so a red check or a refused title stops it here.

Then open the pull request:

```bash
bash ${BU_ROOT}/app git pr
bash ${BU_ROOT}/app git pr --draft
```

Expected output: a line `push` with the branch name, and a line `pull request` with the URL.

What the apply does, in order:

1. Refuses on the main branch (`GIT_WORKFLOW_MAIN_BRANCH`) and on a detached `HEAD`.
2. Runs the minimum check of every component. A red component stops the command before anything is pushed.
3. Builds the title and the body, and lints the title.
4. Pushes `HEAD` to `refs/heads/<branch>` on `origin`, over HTTPS, with your gh login through the gh credential helper. Repository hooks are off for this push, because the check has just run.
5. Opens the pull request with `gh pr create` into the main branch, with the title and the body. `--draft` opens it as a draft.

The App token is not used here. The pull request is opened as you.

### Title

| Commits on the branch that the main branch lacks | Title |
|---|---|
| One | The subject of that commit, for example `feat: add login`. |
| Several, branch `feat/add-login` | The branch made readable: `feat: add login`. |
| Several, branch without a type, for example `Topic name` | `Topic name` is not a conventional header, so the title is refused. |

The title is never rewritten. A refused title stops the command, and you fix the branch name or the commit.

Length rule. GitHub appends ` (#<number>)` to the squash subject, so the header limit of 100 characters applies to the title plus that suffix:

- `app git pr` lints the title with a fixed reserve of ` (#9999)`, 8 characters. A title of 93 characters or more is refused locally.
- CI lints the title plus the real suffix of the pull request. A title of 96 characters or more always fails; 94 and 95 characters fail once the pull request number has three digits, and 93 characters once it has four.
- Keep titles at 92 characters or less.

If the title must change after the pull request is open, edit the title on GitHub. CI lints the title again when it is edited.

| Message | Exit | Fix |
|---|---|---|
| `pr: the current branch is master, open the pull request from another branch` | 1 | Work on a branch from `start`. |
| `pr: HEAD is not on a branch` | 1 | Switch to the branch of the change. |
| `pr: the minimum check is red, nothing was pushed` | 1 | Run `check`, fix the named commit or command. |
| `pr: the branch <name> has no commit that master lacks` | 1 | Commit the change first. |
| `pr: the title '...' did not pass commitlint, ... nothing was pushed` | 3 | Read the reason above it. Rename the branch or reword the single commit. Keep the title at 92 characters or less. |
| `pr: no developer login, run: gh auth login` | 3 | Run `gh auth login`. |
| `commitlint is not installed: run npm install in ...` | 1 | Run `npm install` in the plugin root. |
| `remote: the repository has no remote origin` | 4 | Add the `origin` remote. |

Never run `gh pr create --fill`. It takes the title from the commit list and skips the title lint, and the title is the subject that lands on `master`. Use `app git pr`.

## 5. Merge

Merge on GitHub with **Squash and merge**. The rulesets of the production stage allow only squash merges and linear history, so merge commits and rebases are refused. See [rulesets-and-ci.md](rulesets-and-ci.md).

The merge is allowed when the required status check `check` passes. That check is the CI job of `status-checks.yml`: the commit lint of the pull request, the title lint, and the checks of `components.yaml`.

After the squash, `master` has one new commit. Its subject is the pull request title with ` (#<number>)` appended, and its parent is the previous head of `master`. The release of the next version reads this subject.

No `app git` command merges a pull request.

## 6. After the merge

1. Update the main branch with git: `git switch master` and `git pull --ff-only`. The next `start` refuses until the local main branch equals `origin/master`.
2. List what can be removed: `bash ${BU_ROOT}/app git branch-cleanup --dry-run`. A squash-merged branch is shown as `merged`. Protected names (`master`, the release branch, `main`, `develop`, and a few others) are skipped. A branch that is not merged and whose last commit is older than `PLUGIN_EDOTZ_GIT_WORKFLOW_STALE_DAYS` days (default 30) is shown as `stale`.
3. Delete the merged branches: `bash ${BU_ROOT}/app git branch-cleanup`. It asks once; `--force` skips the question, and `--local-only` or `--remote-only` limits it to one side. The remote branches are deleted with your `gh` login, one push per branch.

`branch-cleanup` deletes a branch only when git itself proves that every commit of it is on the main branch (merge, rebase, or a squash merge); a branch that only a merged pull request names is kept, because its tip can hold commits the pull request did not have. It never deletes the checked-out branch, a protected name (the main and release branches, the patterns of `GIT_WORKFLOW_LEGACY_BRANCHES`, `release-please--*` and `backport/*`), a branch at the same commit as the main branch (nothing tells it from one just cut), or a branch that is not merged. The remote branches are deleted only when `origin` is on github.com: the command fetches `origin` first and pushes each deletion with a lease on the tip it proved merged, so a commit pushed in the meantime keeps the branch. Each branch gets one line, `deleted <branch>`, `kept <branch>` or `failed <branch>`, with the reason. Do not rely on `git branch -d`: a squash commit is no descendant of the branch, so only `-D` deletes it by hand.

## 7. Status

```bash
bash ${BU_ROOT}/app git workflow-status
```

Prints JSON and writes nothing. The keys are `current_branch`, `current_version`, `sync_status` (`ahead_of_release`, `behind_release`), `working_tree`, `unreleased_commits` (counts of `feat`, `fix` and breaking commits, and up to 50 `details`), `components` (per component `latest_release`, `commits_since_release` and `release_branch`, which is `on`, `behind` or `absent`), and `runs` (the last five workflow runs). `runs` is empty without a gh credential or a network. The shape, with illustrative values:

```json
{
  "current_branch": "feat/add-login",
  "components": [
    { "name": "web", "latest_release": "v1.2.0", "commits_since_release": 3, "release_branch": "on" }
  ],
  "runs": []
}
```

## Hooks that guard the loop

| Git hook | Installed by | Runs | Blocks when | Not run by |
|---|---|---|---|---|
| commit-msg | `app git shims` | `bin/hooks/commit-msg/conventional`, which runs `app git lint-commit <file>` | The message is refused. | `app git commit`, which lints itself |
| pre-push | `app git shims` | `bin/hooks/pre-push/minimum-check`, which runs `app git check` for all components | The check is red. | `app git pr`, which runs the same check before it pushes |

The session-start hook of Claude Code runs `app git shims` at the start of a session. It is advisory: it reports a problem and does not block.

How the shims work:

- A shim is a small file in the hooks directory of git (`core.hooksPath`, or the common git directory, which worktrees share). It calls `agentic-os hook trigger <hook>`. The `agentic-os` command must be on your `PATH`. Without it, git reports that `agentic-os` is not found and the commit or push fails.
- `app git shims` installs or replaces the shims that it owns. A hook file that is not an agentic-os shim is left as it is and reported with exit 3.
- `app git shims --check` reports what is missing or stale and changes nothing.

Never use `--no-verify`. It skips the commit-msg and pre-push hooks locally. CI lints the same commits and the title, so a bypass is caught on the pull request instead.

## The loop in Claude Code

Each slash command runs the same `app git` command with the arguments you type, and reports its output unchanged.

```text
/git:start feat add-login
/git:commit src/login.js --message "feat(login): keep the session after a reload" --yes
/git:check
/git:pr --dry-run
/git:pr
```

Rules for the slash commands:

- `/git:commit` needs `--message` and `--yes` in Claude Code. The confirmation reads from standard input, and the shell of a Claude Code session gives none. Without them the commit is declined with `commit: not confirmed, nothing was committed`. Run `bash ${BU_ROOT}/app git commit` in a terminal to get the prompt.
- Commands run in the directory of the session, on the branch that is checked out there.
- Slash commands for release, promote, split and rules-sync are listed in [command-reference.md](command-reference.md).

## Rules

- Never `gh pr create --fill`. Use `app git pr`.
- Never `--no-verify`.
- Never commit to, push to, or open a pull request from `master`.
- Never force-push `master`.
- Name the branch `<type>/<name>` after the subject you want.
- Never amend a published commit. Reword only your own unpushed commits, or add a new one.

## See also

- [Command reference](command-reference.md): every `app git` command and slash command, with options and exit codes.
- [Release and promote](release-and-promote.md): how commits become versions.
- [Monorepo and split](monorepo-and-split.md): components and baseline tags.
- [Rulesets and CI](rulesets-and-ci.md): the branch rules and the required check.
- [Troubleshooting](troubleshooting.md): symptoms and fixes.
