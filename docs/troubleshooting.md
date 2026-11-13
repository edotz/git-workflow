# Troubleshooting

Each table gives a symptom as the tool prints it, its cause, and the fix. Commands are written for a consuming project as `bash ${BU_ROOT}/app git <command>`. Messages are quoted from the sources; `...` marks a value that the tool fills in. The adoption order is in [adopting-in-a-project.md](adopting-in-a-project.md), the exit codes and options in [command-reference.md](command-reference.md).

## Setup and environment

| Symptom | Cause | Fix |
|---|---|---|
| `Command not found: docker` | Docker is not installed, or `docker` is not on the `PATH` of the shell that runs `app`. | Install Docker, open a new shell, and check `command -v docker`. |
| `tool image build failed: <path>/docker-compose.yaml` | The tool image is built on the first tool run. The build fails when the Docker daemon is not running, or when a pinned download fails. | Start Docker and run the command again. The downloads are checked against pinned checksums in `.env.defaults`; do not edit the pins to get past a failed check. |
| `Command not found: gh` or `Command not found: curl` | A host tool that the token request or the pull request needs is missing. | Install the tool and run `gh auth login`. |
| `commitlint is not installed: run npm install in <plugin root>` | The plugin root has no `node_modules`. `lint-commit` runs commitlint from there. | Run `npm install` in the plugin root. |
| `check command failed: ...` with `shellcheck: not found`, in a new worktree | `components.yaml` runs the tools from `node_modules/.bin`, and a new worktree has no `node_modules`. | Run `npm install` in the worktree, or run the check from the main clone. |
| `workflow-setup validate` shows a branch that is not the one in `.env` | A `GIT_WORKFLOW_*` variable is exported in the shell. The environment wins over `.env`. The sandbox pilot saw a release branch named from a shell export. | Find the variable with `env \| grep GIT_WORKFLOW_`, run `unset` on it, and run `bash ${BU_ROOT}/app git workflow-setup validate` again. |
| `git fetch` or `git push` fails with a permission error on an `ssh` remote, such as `git@github.com:<owner>/<repo>.git`, when no key is set up for it | Your own git commands use the remote `origin` as configured. The plugin's own fetches and pushes (release, promote, split, pr) always use `https://github.com/<owner>/<repo>.git` with the `gh` credential helper, so they are not affected by the remote form. | Point `origin` at the https URL (`git remote set-url origin https://github.com/<owner>/<repo>.git`) and let git use `gh` as the credential helper (`gh auth setup-git`, a `gh` command that these sources do not contain). The plugin reads both URL forms to find the repository. |
| `workflow-setup validate` refuses a branch name with whitespace | `GIT_WORKFLOW_MAIN_BRANCH` or `GIT_WORKFLOW_RELEASE_BRANCH` holds a space. | Set a branch name without whitespace in `.env`. |
| `rules: <name> needs GIT_WORKFLOW_RELEASE_BRANCH` or `... needs GIT_WORKFLOW_LEGACY_BRANCHES, the comma separated branch patterns` | The variable is set but blank. An unset `GIT_WORKFLOW_LEGACY_BRANCHES` is not an error: the legacy ruleset is skipped. | Set the variable to a branch name, or unset it. |
| `plugin registry not built` when a commit runs in a worktree | The plugin path in `.agentic-os/project.yaml` is relative and does not resolve from the worktree location. The sandbox pilot saw this with a worktree under `$HOME`. | Point `GIT_WORKFLOW_WORKTREE_DIR` at an absolute folder from which the relative plugin path resolves, or use an absolute `path` for the plugin. |
| `Local master is not in sync with origin/master` when `start` runs | The local main branch is behind origin. | Run `git fetch origin`, update local `master` from `origin/master`, and run `start` again. |

## Tokens and the token service

The token step is the first write of release, promote, split and rules-sync. A refusal there leaves nothing written, so the fix is to correct the cause and run the command again. The message has the form `token: <reason> (HTTP <status>, <owner/repo>, set <set>)`.

| Symptom | Cause | Fix |
|---|---|---|
| `token: service unreachable: <url>` | The token service is not running, or the URL or port does not match. The default is `http://127.0.0.1:8790`. | Start the `token-service` service of the plugin's `docker-compose.yaml`. Set `TOKEN_SERVICE_PORT` or `TOKEN_SERVICE_URL` if the port differs. Check with the `curl` line of the checklist: `404` means the service is up. |
| Service container exits with `no private key in <path>` | The key file is not mounted. The compose file mounts `TOKEN_SERVICE_KEY_FILE`, and it falls back to `/dev/null` when the variable is unset; or the file holds no PEM private key. | Set `TOKEN_SERVICE_KEY_FILE` to the App's key file on the host and start the service again. Do not copy the key into the repository, an image, a log or a note. |
| `TOKEN_SERVICE_APP_ID and TOKEN_SERVICE_KEY_PATH are required` | The token service was started without its two settings. | Set `TOKEN_SERVICE_APP_ID` and `TOKEN_SERVICE_KEY_PATH` before starting it. |
| `token: login not accepted: gh has no login, run gh auth login` | No `gh` login on this machine. | Run `gh auth login`. |
| `token: login not accepted (HTTP 401, ...)` | The `gh` login is not accepted by the service. | Run `gh auth login` again. |
| `token: not a member (HTTP 403, ...)` | The login is not an active member of the organisation. | Ask an organisation owner to add the account. The membership must be `active`. |
| `token: repository not installed (HTTP 404, <owner/repo>, set <set>)` | The App is not installed on that repository. Child repositories of split components need it too. The nodejs-project migration hit this on two children. | Install the App on the repository in the organisation settings, then run again. |
| `token: repository not in the organisation (HTTP 403, ...)` | The `owner` or `repo` in `components.yaml` names a repository outside the organisation. | Correct `owner` and `repo`. |
| `token: refused by the service: ...` | The service refused the request for a reason it does not name here. | Read the reason in the message. The service logs neither token. |

## Branch settings and rulesets

| Symptom | Cause | Fix |
|---|---|---|
| `rules-sync --apply` fails with a 403, `Resource not accessible by integration`, on a ruleset write | The App has administration read only. Ruleset writes need administration write. | Raise the App's administration permission to write and accept the change on the installation. |
| `skipped` for `legacy` in the rules-sync dry run | `GIT_WORKFLOW_LEGACY_BRANCHES` is unset. | Expected when the repository has no legacy line. |
| `foreign ruleset <id> <name> covers <branch>` | A ruleset that rules-sync does not manage covers the branch. rules-sync never deletes or edits it. | Decide with the developer. To remove it, delete it in the repository settings. |
| `classic protection covers <branch>, required checks: ...` | Classic branch protection still applies to the branch. | After the rulesets exist, remove the classic protection for that branch (settings or API). Do it before merging the pull request that removes the workflows its required checks name. |
| `gh api repos/<owner>/<repo>/branches/<branch>/protection` prints `Branch not protected` | Expected after the classic protection is removed. | None. |
| A `release` ruleset appears on the wrong branch, for example `0.x` | The release branch name came from a shell export when `rules-sync --apply` ran. | Fix the variable (see the setup table), then run `rules-sync --apply` again. The ruleset follows the name. |
| `rules-sync --apply` left `master` without rules | The `development` stage gives the `master` ruleset no rules. | Apply with `--stage production`. |
| A repeated `rules-sync --apply` reports `update` for rulesets that did not change | Seen in the sandbox pilot. | Compare the ruleset in the repository settings if it matters. |
| `push declined due to repository rule violations` on a direct push to `master` | A ruleset applies to `master` that the App does not bypass. The sandbox pilot had a repository ruleset `master-protection` that denied the push. | Push through a pull request. Remove the foreign ruleset only with the developer's decision. |

## Commits and pull request titles

The pull request title becomes the squash subject on `master`, so it must be a valid conventional commit header. The header limit is 100 characters, and GitHub appends ` (#N)` to the squash subject. The title lint therefore counts the suffix: the title plus ` (#N)` must fit 100 characters. `app git pr` reserves ` (#9999)` (8 characters), so it refuses a title of 93 characters or more. CI adds the real suffix: with a three-digit pull request number it fails a title of 94 characters or more, with a four-digit one 93 or more.

The allowed types are the ones of `commitlint.config.mjs`: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.

| Symptom | Cause | Fix |
|---|---|---|
| `pr: the title '<title>' did not pass commitlint, see the reason above, nothing was pushed` | The title is not a conventional commit header. `app git pr` uses the subject of a single commit as the title. | Reword the single commit, or make the branch name a conventional type (see the next row). The title is never rewritten by the plugin. |
| The title of a multi-commit branch starts with a word that is not a type, for example `hotfix: ...` | With several commits, the title is built from the branch name as `<prefix>: <rest>`. The prefix `hotfix` is not a type. | Rename the branch to a conventional type, for example `fix/<name>`. `start` accepts only the types above. |
| The title is refused for length by commitlint, or `pr` refuses a title of 93 characters or more | The title plus ` (#N)` is longer than 100 characters. | Shorten the title of the open pull request before it merges. The squash subject is the title. |
| A squash subject over 100 characters is on `master` | A pull request title was longer than the limit at merge time. | Keep the title under the limit before merging. A commit already on `master` is not changed by the plugin. |
| `commit lint failed: <subject>` with `type may not be empty` for a `Merge ...` or `Revert ...` subject | commitlint passes only the forms it ignores by default: `Merge branch`, `Merge pull request` and `Revert ...`. Any other subject starting with `Merge` or `Revert` is refused. | Write a conventional subject. Do not bypass the lint. |
| `commit lint failed: <subject>` from `check`, `pr` or the pre-push guard, for a commit you did not write today | `check` lints every commit since the latest tag of the component, in every path of the repository, not only the component's paths. A non-conventional commit in that range fails every check. | The commit cannot be reworded once pushed. Decide with the developer whether the baseline tag of the component must move; do not bypass the lint. |
| `pr: the minimum check is red, nothing was pushed` | A component's check or commit lint is red. | Run `bash ${BU_ROOT}/app git check` to see the component and the step that failed. |
| `pr: the current branch is master, open the pull request from another branch` | `pr` was run on the main branch. | Commit on a feature branch, for example from `bash ${BU_ROOT}/app git start`. |
| `pr: the branch <branch> has no commit that master lacks` | The branch has nothing to propose. | Commit the change first. |
| `pr: HEAD is not on a branch` | Detached HEAD. | Check out a branch. |
| Pull request check `check` stays pending, or the pull request is blocked | The workflow has a `paths:` filter that matches no changed file, so `check` never reports. | Remove the path filter from `status-checks.yml`. |

## Release and promote

| Symptom | Cause | Fix |
|---|---|---|
| `Nothing to release: no component changed since its latest tag` | Nothing counts: the baseline tag is on HEAD, or the commits since the tag are only `chore`, `ci`, `docs`, `test`, `style`, `refactor` or `build`, or they lie outside the component's paths. | Run `git log <tag>..HEAD -- <paths>` to see the commits. A `feat`, `fix`, `perf` or breaking commit releases. |
| `release: apply runs on master, the current branch is <branch>` | `release --apply` was run off the main branch. | Switch to `master` and run again. |
| `release: the working tree has uncommitted changes, nothing was changed` | The tree is not clean. | Commit or stash your own changes, then run again. |
| `release: the minimum check is red, nothing was changed` | A component check failed. | Run `bash ${BU_ROOT}/app git check`, fix the failing step, and run again. |
| `version: <file> has no version key, Composer reads the tag: remove it from version_files` | A `composer.json` in `version_files` has no `version` key. | Remove that file from `version_files`. |
| `version: <file> takes plain X.Y.Z versions only, got <version>` | `--pre` was given for a component that lists `ext_emconf.php`. That writer takes final versions only. | Make the final release of that component without `--pre`. |
| `version: <file> holds <n> 'version' lines, expected exactly one` | The `ext_emconf.php` writer needs exactly one `'version' =>` line. | Keep one such line in the file. |
| `release --dry-run` shows `pending` for a tag that is on HEAD | A previous apply stopped after the commit and the tag, before the push or, in a repository of one component, the GitHub Release. The sandbox pilot saw an interrupted apply. | Run `bash ${BU_ROOT}/app git release --apply` again. The release is idempotent: it creates only what is missing. |
| `Could not resolve host: github.com` during apply; the commit and the tag stay local | Network loss during the push. The sandbox pilot saw this. | Restore the network and run `bash ${BU_ROOT}/app git release --apply` again. |
| `promote: <tag> is not a release tag, its commit reads '<subject>'` | The tag is not on a release commit. A release commit reads `chore(<component>): release <tag>`. | Promote the tag of the release commit, not a tag on another commit. |
| `promote: <branch> is not a fast-forward ... run again with --apply --confirm <owner/repo>` | The first move of the release branch after a migration is a baseline. | Expected. Run the dry run, then the apply once with `--confirm`. |
| `promote: the tag legacy/pre-promote of <slug> could not be pushed, it may exist at another commit` | A `legacy/pre-promote` tag already exists on the remote at another commit. | Check the existing tag. Rename or delete it on the remote yourself, with the developer's decision, then run again. |
| `ls-remote answered with 128` during split or promote | A transient failure reading the remote. The nodejs-project migration saw it once. | Run the command again. |

## Split

| Symptom | Cause | Fix |
|---|---|---|
| `split: the default branch of <slug> is <x> but GIT_WORKFLOW_MAIN_BRANCH is <y>: ... nothing was pushed` | The child's default branch is not the main branch of the monorepo. | Create `master` in the child and make it the default branch. Run the dry run again. |
| `split: <slug> does not descend from the split: its old head <sha> would be kept as legacy/pre-split ... run the dry run, then again with --confirm <slug>` | The child is unrelated to the split. The first split of an existing child always stops here. | Expected. Read the dry run, then apply once with `--confirm edotz/<child>`. The old head stays as `legacy/pre-split`. |
| Dry run warning `the child is unrelated to the split: it needs a baseline` or `the histories diverged` | Same as above; the dry run reports it and changes nothing. | Apply with `--confirm` once the dry run is right. |
| `--confirm` names another repository and the apply stops | The `owner/repo` after `--confirm` is not the child of the component. | Give the child of that component. |
| `split: the tag legacy/pre-split of <slug> could not be pushed, it may exist at another commit` | The child already has a `legacy/pre-split` tag at another commit. | Rename or delete it on the child with the developer's decision, then run again. |
| Warning `tag <name>: skipped: <slug> has it at <sha>, the split of <tag> is <sha>: it is not moved` | A child tag exists at another commit. | Expected. The tag is not moved. Decide with the developer if it must change. |
| `splitsh-lite printed no commit` for `<component>`, with `no history <component>/vX.Y.Z` | A component tag sits on a commit from before the component's paths existed, so no split history exists for it. | Move the tag to a commit that touches the component, with the developer's decision. The sandbox pilot removed its own tag and re-tagged. |
| `splitsh-lite failed` in a linked worktree | The sandbox pilot saw this: the tool image could not use the git directory of a linked worktree. The mount of the common git directory is in the code; re-check on your version. | Run `split` from the main clone. |
| `split --apply` without a component | The apply needs exactly one component. | Name the component, or use `--dry-run` for all of them. |
| Second `split --apply` reports `at the split head ... nothing to apply` | Expected: the child already has the split head and its tags. | None. |

## Hooks and shims

| Symptom | Cause | Fix |
|---|---|---|
| `<hook>: conflict, <path> is not an agentic-os shim and stays as it is` (exit 3) | A foreign hook file sits where the shim goes. | Move that file aside with the developer's decision, then run `bash ${BU_ROOT}/app git shims` again. |
| `bash ${BU_ROOT}/app git shims --check` exits 1 and names `missing or stale` | A shim is missing or differs from the plugin's shim. | Run `bash ${BU_ROOT}/app git shims`. |
| The shim prints `No hook registry ... no hooks run`, and the pre-push guard does nothing | `bash ${BU_ROOT}/app hooks install` was not run. The shim alone registers nothing. | Run `bash ${BU_ROOT}/app hooks install`, then `bash ${BU_ROOT}/app hooks enable pre-push minimum-check`. |
| The guard is installed but a push goes through a non-conventional commit | The hook is registered but disabled. The sandbox pilot saw `app hooks install` register the plugin hook disabled. | Run `bash ${BU_ROOT}/app hooks status` and enable the hook with `bash ${BU_ROOT}/app hooks enable pre-push minimum-check`. |
| `agentic-os: not found` on a commit or a push | The shim runs `agentic-os hook trigger`, and the shell has no `agentic-os` on `PATH`. The tool image has no `agentic-os` either. | Put `agentic-os` on the `PATH` of the host shell. The plugin's own pushes run without repository hooks, because the checks already ran on the host. |

## Worktrees and branches

| Symptom | Cause | Fix |
|---|---|---|
| `Branch exists locally: <branch>` or `Branch exists on origin: <branch>` from `start` | `start` refuses an existing branch instead of checking it out. | Choose another name, or work on the existing branch. |
| `start` refuses `<type>` | The type is not one of the commit types. | Use one of the types listed in the pull request table above. |
| `branch-cleanup` does not list a squash-merged branch as merged | The merged pull request lookup needs your `gh` login and the remote. | Run `gh auth login` and make sure `origin` is the repository. |
| `workflow-status` prints an empty `runs` field | No `gh` credential, no network, or the runs cannot be read. | Expected without a credential. Run `gh auth login` for the runs. |

## Never do this

- Do not force-push `master`, and do not move a child's `master` by hand. A split replaces a child only with `--confirm`, keeps the old head as `legacy/pre-split`, and checks the lease.
- Do not open a pull request with `gh pr create --fill`. The plugin builds the title from the commits and lints it before anything is pushed; `--fill` skips that check.
- Do not use `--no-verify`, and do not disable hooks in your own commands. The plugin runs its own pushes with `core.hooksPath=/dev/null` only after the checks ran on the host.
- Do not move an existing component tag to make a release happen. Split skips a child tag that sits at another commit and leaves it where it is. Delete or move a tag only with the developer's decision.
- Do not run `--apply` or `--confirm` without the dry run first.
- Do not write a token, the App's key or a key path into a file, a note, the repository or a command line. The plugin keeps tokens in memory only.
- Do not set `GIT_WORKFLOW_*` variables in the shell to change a setting. Put them in `.env`, and check with `env | grep GIT_WORKFLOW_`.
- Do not run `split` or `release` from a linked worktree. Use the main clone.
