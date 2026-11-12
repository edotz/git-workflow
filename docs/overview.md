# git-workflow plugin: overview

The `edotz.git-workflow` plugin is the git and GitHub workflow of the edotz repositories. It runs on the developer's machine as `app git <command>` and as the slash commands `/git:start`, `/git:commit`, `/git:check`, `/git:pr`, `/git:release`, `/git:promote`, `/git:split` and `/git:rules-sync` in Claude Code. It is a plugin of the agentic-os framework; the `app` entry point comes from the framework.

This page explains the model. The other manuals give the steps, the options and the details; the table at the end says which one to read.

## Why it exists

The workflow it replaces ran as a chain of GitHub Actions. A release could pass through up to five chained pull requests and workflows, backport pull requests conflicted asynchronously, a release could not be previewed or repaired locally, and every write was tied to one personal token.

The plugin replaces that with one local, deterministic process:

| Before | Now |
|---|---|
| release-please opened release pull requests | `app git release` makes one release commit and its tag on master, locally, after a dry run |
| backport workflow opened backport pull requests | the release branch follows a release tag by fast forward (`app git promote`) |
| merge-split-repo, sync-to-monorepo workflows | `app git split` pushes a component to its child repository |
| post-release workflow | the GitHub Release is created by `app git release` |
| commit-lint, php-cs-fixer workflows | the commit lint runs locally in a commit-msg hook and in the single CI workflow |
| personal token did every write | a GitHub App makes the releases, promotes, splits and ruleset changes, with short-lived tokens |

The only GitHub workflow left in a consuming project is `status-checks.yml`. Everything else of the old approach is retired.

The plugin ends at the GitHub Release. Publishing, deployment and provisioning belong to the consuming project. The plugin ships no LLM provider: when a commit has no `--message`, the message is drafted by the provider of the running session.

## Mental model in one page

### Actors

| Actor | What it does | Where it runs |
|---|---|---|
| Developer | Starts work, commits, opens pull requests, decides when to release | Own machine |
| Claude Code | Runs the slash commands; drafts commit messages; starts the shim installation at session start | Own machine |
| `app git` modules | The commands; the git, gh, git-cliff and splitsh-lite calls that touch the remote or write go through the tool image | Own machine, on the host shell |
| Tool image | Docker image with git, jq, gh, git-cliff and splitsh-lite; each tool call is one ephemeral container | Docker on the developer's machine |
| Token service | Checks the developer's GitHub login and organisation membership, then issues an installation token of the GitHub App for one repository and one permission set | Local service on loopback, a host process or a container |
| GitHub App `git-workflow-app` | Holds the write rights of release, promote, split and rules-sync | GitHub |
| GitHub | Pull requests, rulesets, the status check, Releases | GitHub |

The developer's own `gh` credential does the daily work (push, pull request). Only the four commands that write release state use the App, through the token service. The App cannot publish npm packages.

### Branch model

| Branch | Setting | Role |
|---|---|---|
| master | `GIT_WORKFLOW_MAIN_BRANCH` (default `master`) | Where work lands and where releases are made. Every release is a commit on master. |
| Release branch | `GIT_WORKFLOW_RELEASE_BRANCH`, for example `1.x` or `2.x` | Follows a release tag by fast forward through `app git promote`. It never gets its own commits. |
| Legacy branches | `GIT_WORKFLOW_LEGACY_BRANCHES` | Old release lines. They get the legacy ruleset. `app git release` only runs on the main branch. |
| Feature branches | `<type>/<name>`, created by `app git start` in the checkout you work in | One change each, branched from master without an upstream. The pull request squash-merges it into master. |

The release branch moves only through `app git promote`, and its ruleset blocks deletion and non-fast-forward pushes in both stages. The master ruleset requires a pull request, so direct pushes are refused, but only in the production stage; its development stage has no rules and the file has no `non_fast_forward` rule for `master`. Never force push master by hand in either stage.

### Components and `components.yaml`

A repository declares its units in `components.yaml` at the repository root. Each unit is a component with its own version, checks and, optionally, a child repository.

```yaml
components:
  - name: web
    paths: [web]
    version_files: [web/package.json]
    checks: ["npm test --prefix web"]
  - name: lib
    paths: [lib]
    split: yes
    owner: example-org
    repo: lib
```

- A repository with one component is a single-component repository; its tags are `vX.Y.Z`.
- A repository with two or more components tags each one with its name as prefix: `web/vX.Y.Z`.
- `version: none` marks a component that is not versioned.
- `split: yes` sends the component to the child repository named by `owner`, `repo` and `host`.

Every field and rule is in [Configuration](git-workflow-configuration.md).

### Versions and tags

The version of a component is counted from the commits after its latest stable tag. Only `feat`, `fix`, `perf` and breaking commits make a release: `chore`, `ci`, `docs`, `test`, `style`, `refactor` and `build` commits in a component path do not. Because the count starts at the latest tag, the place of the tag in the history does not matter.

| Tag | Meaning |
|---|---|
| `vX.Y.Z` or `<name>/vX.Y.Z` | A component release. Points at its release commit. |
| `vX.Y.Z-<channel>.N` | A pre-release made with `--pre <channel>`. |
| Baseline tag | The already released version of a component, put on the last commit that touches it when a repository joins the plugin. It is not a release commit. The count starts after it. |
| `legacy/pre-promote` | The old head of a release branch that promote replaced (baseline mode). |
| `legacy/pre-split` | The old head of a child repository that split replaced (baseline mode). |

The release commit has the subject `chore(<component>): release <tag>`. It holds the version files, the CHANGELOG and the README lines between the release markers. `app git promote` accepts only a tag whose commit has this subject.

### Stages

The stage is a setting of the rulesets: `GIT_WORKFLOW_STAGE` is `development` (default) or `production`, and `app git rules-sync --stage` applies it to the master ruleset. No other command reads it.

| | development | production |
|---|---|---|
| Changes to master | Direct push allowed: the master ruleset has no rules | Pull request required, squash merge only, linear history |
| Required status check | None on GitHub | `check` (commit lint, title lint, declared checks) |
| Local guard | The pre-push shim runs the minimum check when it is installed | The same |
| Release and promote | Same commands, same App | Same commands, same App |

The release branch and the legacy branches have their own rulesets in both stages: no deletion, no force push, linear history, and the App as the only bypass actor. See [Rulesets and CI](rulesets-and-ci.md).

### What runs locally and what runs in CI

| Step | Local (developer machine) | CI (GitHub Actions of the repository) |
|---|---|---|
| Commit message lint | Yes: commit-msg shim, and `app git commit` lints before it commits | Yes: the commit lint of the pull request commits |
| Pull request title lint | Yes: `app git pr` lints the title before it pushes | Yes: the title of the pull request |
| Declared checks of `components.yaml` | Yes: `app git check`, the pre-push shim, `app git pr`, `app git release` | Yes: `status-checks.yml` runs them on each pull request |
| Opening the pull request | Yes: `app git pr`, as the developer | No |
| Release commit, tag, push, GitHub Release | Yes: `app git release --apply`, as the App | No |
| Promote, split, rulesets | Yes: `app git promote`, `split`, `rules-sync`, as the App | No |
| Squash merge | No: on GitHub, by the developer | No |

The only workflow of a consuming project is `status-checks.yml`. It has one job, `check`, which is the required status check of the production ruleset.

### Flow

```text
Developer (shell or Claude Code)
  |
  | app git start feat add-login        branch feat/add-login, checked out
  | app git commit <paths>              conventional commit, linted before it is made
  | app git check                       commit lint since the last tag, plus declared checks
  | app git pr                          push as the developer, open the pull request
  |                                          |
  |                                          v
  |                          GitHub: pull request, status check "check"
  |                                          |  squash merge (production stage)
  |                                          v
  |                                       master
  |                                          |
  | app git release --dry-run           preview: version, tag, files, notes
  | app git release --apply             release commit and tag on master, push,
  |                                     GitHub Release  (App, contents set)
  | app git promote <tag> --apply       release branch fast-forwards to the release
  |                                     commit of <tag>  (App, contents set)
  | app git split <component> --apply   component tags and split head to the child
  |                                     repository  (App, split set)
  | app git rules-sync --apply          rulesets from bin/config/rulesets.yaml
  |                                     (App, administration set)
  v
```

## Glossary

| Term | Meaning |
|---|---|
| Baseline tag | A tag that marks the version already released before a repository joined the plugin. It sits on the last commit that touches the component, is not a release commit, and the version count starts after it. |
| Release commit | The commit `chore(<component>): release <tag>` that holds the version files, CHANGELOG and README of one release. Promote accepts only tags on such a commit. |
| Release branch | The branch named by `GIT_WORKFLOW_RELEASE_BRANCH`. It follows a release tag by fast forward and gets no commits of its own. |
| Legacy branch | An older release line named in `GIT_WORKFLOW_LEGACY_BRANCHES`. It is covered by the legacy ruleset and is not released by `app git release`. |
| Component | A named unit of `components.yaml` with its paths, its version, its checks and, optionally, a child repository. |
| Child repository | The separate repository that a component with `split: yes` is published to. It receives the component's head and its tags. |
| Ruleset | A GitHub branch rule object. The plugin uses rulesets, not classic branch protection. The rules are in `bin/config/rulesets.yaml` and are applied by `app git rules-sync`. |
| Minimum check | `app git check` for one component: the commit lint of the commits since its latest tag, then each command of its `checks`. It runs before a pull request, before a push and before a release. |
| Installation token | A short-lived token of the GitHub App, issued by the token service for one repository and one permission set. It is held in a shell variable and never written to a file. |
| Tool image | The Docker image `edotz-git-workflow-tools` with git, jq, gh, git-cliff and splitsh-lite. The tools run as ephemeral containers of it; the read-only checks and the worktree library use the host git. |
| Shim | A small hook script in the git hooks directory that calls `agentic-os hook trigger <event>`. `app git shims` installs them. |
| Pre-release | A version with a channel, `X.Y.Z-<channel>.N`, made with `app git release --pre <channel>`. Its GitHub Release is marked as a pre-release. |
| Promote | Moving the release branch to the release commit of a release tag, with `app git promote`. |
| Split | Publishing a component to its child repository with `app git split`. |

## Decision table

| I want to ... | Read |
|---|---|
| Start a change, commit, check, open a pull request, clean up | [Daily loop](daily-loop.md) |
| Look up the options, arguments and exit codes of a command | [Command reference](command-reference.md) |
| Understand versions, a release, a pre-release, promote or baseline mode | [Release and promote](release-and-promote.md) |
| Work with a monorepo, its child repositories, baselines or legacy tags | [Monorepo and split](monorepo-and-split.md) |
| Write `components.yaml`, set environment variables, choose a stage | [Configuration](git-workflow-configuration.md) |
| Understand rulesets, `rules-sync`, the CI workflow, hooks and shims | [Rulesets and CI](rulesets-and-ci.md) |
| Understand the GitHub App, the token service and its permission sets | [GitHub App and token service](github-app-and-token-service.md) |
| Adopt the plugin in a project or migrate from release-please | [Adopting in a project](adopting-in-a-project.md) |
| Fix a failing command, a red check or a refused push | [Troubleshooting](troubleshooting.md) |
| Change the plugin's code, add a command or an option | [Architecture](architecture.md) |
| Find the manual for any question | [Index](README.md) |

## Never do

- Never force push master or the release branch.
- Never create a pull request with `gh pr create --fill`: the pull request title must be the conventional header of the squash commit, and `app git pr` checks it.
- Never skip the hooks with `--no-verify`: the commit-msg lint and the minimum check are the gate of the workflow.
- Never move or delete a tag by hand on the remote. The split skips a child tag that exists at another commit and never moves it; a wrong release is corrected by a new one.
- Never write the developer's token or a key of the App into a file, a command line or a commit.
