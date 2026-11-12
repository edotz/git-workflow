# Rulesets and CI

This manual covers how the branches of a repository are protected: the branch rulesets that the plugin manages, the command that creates them (`rules-sync`), the one GitHub workflow that a consuming repository runs (`status-checks.yml`), and the local hooks that check commits before they leave the machine. The files it describes are `bin/config/rulesets.yaml`, `bin/lib/rules.sh`, `bin/modules/git/rules-sync.sh`, `.github/workflows/status-checks.yml`, `bin/hooks/` and `.git-templates/hooks/`.

The plugin uses rulesets, not classic branch protection. A repository that still has classic protection keeps it until someone removes it; `rules-sync` reports it and never removes it (see [rules-sync](#rules-sync)).

## The managed rulesets

`rules-sync` manages three rulesets, defined in `bin/config/rulesets.yaml`. Each one applies to a set of branches:

| Ruleset | Branches | Applies when |
|---|---|---|
| `master` | the branch named by `GIT_WORKFLOW_MAIN_BRANCH` (default `master`) | always |
| `release` | the branch named by `GIT_WORKFLOW_RELEASE_BRANCH` | the setting is set |
| `legacy` | the patterns of `GIT_WORKFLOW_LEGACY_BRANCHES` | the setting is set |

A ruleset whose setting is unset is skipped with a warning. `master` always applies.

Every ruleset has the same two properties. The ruleset is `active`, and the App is a bypass actor with mode `always`. The App is the actor that releases, promotes and splits (see [GitHub App and token service](github-app-and-token-service.md)): a release commit is pushed straight to `master`, and a promote moves the release branch. A rule that blocks direct pushes would block those pushes, so the App is exempt from the rules; no other actor is.

### The rules of master

These rules apply in the `production` stage. In `development` the `master` ruleset has no rules (see [Stages](#stages)).

| Rule | Setting | What it does | Why |
|---|---|---|---|
| `pull_request` | 0 required approvals; `allowed_merge_methods: [squash]`; no code owner review; no thread resolution requirement | A change reaches `master` through a pull request, and the pull request can only be merged by squash. | The pull request title becomes the squash subject on `master`, so the title is what the history and the release read. |
| `required_status_checks` | context `check`, not strict | The pull request can merge only when the check named `check` has passed. Strict mode is off: the branch need not be up to date with `master`. | `check` is the job of `status-checks.yml`, which lints the commits and the title and runs the declared checks. |
| `required_linear_history` | on | `master` takes no merge commits. | Keeps one squash commit per pull request on `master`. |

Direct pushes to `master` from anyone but the App are refused by the `pull_request` rule. The file has no `non_fast_forward` rule for `master`, so the rule set does not name force pushes separately for `master` in production; the pull request rule still refuses them from anyone but the bypass actor. In `development` no rule applies, so nothing blocks a force push there.

### The rules of release and legacy

| Rule | What it does | Why |
|---|---|---|
| `pull_request` | 0 required approvals; the same review settings as `master`; no merge method restriction | A human changes the release branch through a pull request only. |
| `required_linear_history` | no merge commits | The release branch follows a release tag by fast forward (`promote`), so its history stays linear. |
| `deletion` | the branch cannot be deleted | A release line must stay. |
| `non_fast_forward` | no force push | Force pushes to the release branch are refused for everyone but the App, which moves the branch in `promote`, including the baseline mode that replaces a diverged head with a lease. |

`legacy` has the same rules as `release`, on the branches named in `GIT_WORKFLOW_LEGACY_BRANCHES`. Old lines of a project are kept with these rules so that they cannot be rewritten or deleted by accident.

## Stages

The stage selects the rules of `master`:

| Stage | `master` rules | Set by |
|---|---|---|
| `development` (default) | none; the ruleset exists with the App as bypass actor | `GIT_WORKFLOW_STAGE` unset, or set to `development` |
| `production` | `pull_request` (squash only), `required_status_checks` with `check`, `required_linear_history` | `GIT_WORKFLOW_STAGE=production`, or `--stage production` |

The stage changes only the `master` ruleset. `release` and `legacy` are the same in both stages. A stage that is not listed in `rulesets.yaml` is refused with exit 2.

Set `GIT_WORKFLOW_STAGE` in `.env` for the repository, or pass `--stage` for one run. A plain `rules-sync --apply` uses the value of `.env`.

## Merge settings

Pull requests are squash-merged. Two settings make that the only way:

| Setting | Value | Where |
|---|---|---|
| Allowed merge method | squash only | the `master` ruleset (`allowed_merge_methods`) |
| Squash commit title | the pull request title | the repository's merge settings (the rule the plugin relies on) |
| Repository setting `allow_squash_merge` | enabled | the repository's merge settings |

Merge commits are not allowed on `master`. Two reasons, both from the rules above:

- A merge commit gets the subject `Merge pull request ...`, which is not a conventional commit. The commit lint refuses the type `merge`, because it is not in the list of types of `commitlint.config.mjs`. Every commit on `master` must pass that list.
- `required_linear_history` refuses a history with merge commits.

The repository setting can still list merge commits as an option; the ruleset refuses them for `master`. The title rule is in [Pull request title](#pull-request-title).

## rules-sync

`rules-sync` creates or updates the managed rulesets of the repository of the remote `origin`. Its usage is `bash ${BU_ROOT}/app git rules-sync [--dry-run | --apply] [--stage <stage>]`. Its options are described in [Command reference](command-reference.md).

### Dry run (the default)

The dry run changes nothing. It uses the developer's own `gh` login to read the rulesets; it does not call the token service. For each ruleset it prints one line:

| Outcome | Meaning |
|---|---|
| `create` | the repository has no ruleset of that name; `--apply` creates it |
| `update` | a ruleset of that name exists and differs; `--apply` replaces it |
| `unchanged` | the live ruleset has the same name, target, enforcement, conditions, bypass actors and rules |
| `skipped` | the setting of the ruleset is unset; the reason follows |

Example output of `bash ${BU_ROOT}/app git rules-sync --dry-run` for `edotz/git-workflow` in the development stage, written when the live rulesets carried the production rules:

```text
[rules-sync edotz/git-workflow (stage development, dry run)]

  ✓ master — update
  ✓ release — update
  ! legacy — skipped, rules: legacy needs GIT_WORKFLOW_LEGACY_BRANCHES, the comma separated branch patterns
```

Without `GIT_WORKFLOW_APP_ID` the dry run still works. It cannot compare the bypass actors, so it leaves them out of the comparison and an outcome can read `unchanged` while the bypass actor differs. Set `GIT_WORKFLOW_APP_ID` before you rely on an `unchanged`.

### Apply

`bash ${BU_ROOT}/app git rules-sync --apply --stage production` does the following, in this order:

1. Requires `GIT_WORKFLOW_APP_ID`, and checks that it is digits only. Without it the command stops with exit 3 and writes nothing.
2. Fetches an installation token of the App with the permission set `administration` (write), from the token service. The token is fetched before the first write. If the service refuses or is down, the command stops and nothing is written.
3. Reads the live rulesets by name.
4. For each managed ruleset in file order: builds the body for the stage, replaces the bypass actor placeholder with `GIT_WORKFLOW_APP_ID`, decides `create`, `update` or `unchanged`, and sends `POST` (create) or `PUT` (update) to the Rulesets API. `unchanged` sends nothing.
5. Reports foreign rulesets and classic protection (see below).
6. Drops the token.

The tests show the order: the token request comes before the first write, and a second apply with no change writes nothing.

### Which token

| Run | Credential | Token service |
|---|---|---|
| dry run | the developer's `gh` login | not called |
| apply | installation token of the App, permission set `administration` | called, with the repository of `origin` |

The `administration` permission is needed to write rulesets. The App needs administration write on the repository; with read only, GitHub refuses the write (checked before the production App was set up).

### What rules-sync never does

- It never deletes a ruleset, and never deletes classic protection.
- It never changes a ruleset whose name is not in `rulesets.yaml`.
- It never writes classic protection. The tests check that the apply sends no `PUT` to the protection endpoint.

### Foreign rulesets and classic protection

After the managed rulesets, `rules-sync` looks for anything else that still guards a managed branch:

| Found | Output | Action |
|---|---|---|
| an active ruleset that is not in `rulesets.yaml` and covers `master`, `release` or a legacy branch | `foreign ruleset <id> <name> covers <branch>` (warning) | none; the line names it |
| classic branch protection on a managed branch | `classic protection covers <branch>` with the required checks (warning) | none |
| the read of the classic protection fails for a reason other than "not protected" | `classic protection of <branch> — failed read` (warning) | none |

A protection that answers 404 means the branch is not protected by classic protection and prints nothing. A disabled ruleset is not named.

These two kinds of protection are the reason a migration has a step where the old protection is removed by hand. Removing them is a decision of the migration, not of `rules-sync`. See [Adopting in a project](adopting-in-a-project.md).

## status-checks.yml

`.github/workflows/status-checks.yml` is the only GitHub workflow that a consuming repository needs from the plugin. Its job is named `check`; the required status check of the `master` ruleset is the context `check`, so the job name and the rule must stay the same.

### Trigger and permissions

- Trigger: `pull_request` with the types `opened`, `edited`, `synchronize` and `reopened`, for every base branch. `edited` re-runs the job when the title changes, so a title fix is linted.
- Permissions: `contents: read` and `pull-requests: read`. The workflow uses no secrets and no App token.

### Steps

| # | Step | What it does | Fails when |
|---|---|---|---|
| 1 | checkout | `actions/checkout` with `fetch-depth: 0`, so the commits of the pull request are all present | — |
| 2 | Validate conventional commits | `wagoid/commitlint-github-action@v6` with `configFile: commitlint.config.mjs` lints every commit of the pull request | a commit does not match the rules of `commitlint.config.mjs` |
| 3 | Validate the pull request title | installs `@commitlint/cli@21` and `@commitlint/config-conventional@21` into `$RUNNER_TEMP/commitlint`, then pipes the title to `commitlint --config commitlint.config.mjs` | the title is not a valid conventional header |
| 4 | Run the checks declared in components.yaml | reads each `checks` entry of every component with `yq`, runs it with `bash -c` from the repository root, prints each as a group, and fails the job at the end if any failed | a declared command exits non-zero |

When `components.yaml` is missing, step 4 prints a message and passes. In that case the job checks only the commits and the title.

Step 4 runs on the bare runner. The workflow installs nothing for the declared checks. A check that needs dependencies must install them in its own command, or the check fails with a missing command.

### Pull request title

The title of a pull request becomes the subject of the squash commit on `master`. The rule is that the title must be a valid conventional header **including the suffix that GitHub appends**: GitHub adds ` (#<number>)` to the squash subject. The header limit is 100 characters, so the title must be short enough for the suffix.

- The title lint counts the suffix: CI lints the title plus ` (#<number>)`.
- `app git pr` lints the title plus the fixed reserve ` (#9999)` before it pushes, so a title that is too long for a four digit number is refused locally, before anything is pushed.
- The maximum length of the title is 100 minus the length of the suffix. With a four digit number the title may have 92 characters; with three digits 93; with two digits 94; with one digit 95.

A title that fails is never rewritten by the plugin. Change the title on the pull request; the `edited` trigger runs the job again.

### Set up a repository

1. Copy `.github/workflows/status-checks.yml` from the plugin repository to the same path in the consuming repository.
2. Copy `commitlint.config.mjs` to the root of the consuming repository. Steps 2 and 3 read it from there; keep it identical to the plugin file.
3. Keep a `components.yaml` in the root, with the `checks` each component needs. Make each check runnable on a bare Ubuntu runner.
4. Repository merge settings: squash merge enabled; the squash commit title is the pull request title (`PR_TITLE`). The existing repositories of the organisation use `COMMIT_OR_PR_TITLE`, which is the same for a pull request with one commit.
5. Run `bash ${BU_ROOT}/app git rules-sync --dry-run`, then `--apply` with `GIT_WORKFLOW_APP_ID` and the stage you want. The `check` context is required from then on.
6. Open a pull request. The job `check` runs on it, and its result is the required check of the `master` ruleset.

The workflow needs no secrets. Do not add a secret to it for the title lint or the commit lint.

## Hooks and shims

The plugin installs two git hook shims. The shims call the framework, which runs the hook scripts that the plugin registers.

| Git hook | Shim file | Registered script | What it does |
|---|---|---|---|
| `commit-msg` | `.git-templates/hooks/commit-msg` | `bin/hooks/commit-msg/conventional` | runs `app git lint-commit <message file>` on the message; a refused message stops the commit |
| `pre-push` | `.git-templates/hooks/pre-push` | `bin/hooks/pre-push/minimum-check` | runs `app git check` for every component: the commit lint since the latest tag of each component plus the declared checks; a red component stops the push. The hook exits 0 when there is no `components.yaml`. |

Each shim is a file with the marker `# agentic-os-hook:`, and runs `agentic-os hook trigger <key>`. The mapping of the hook keys to git is `adapters/git/hooks/hooks.yaml`.

### The session-start hook

`bin/hooks/session-start/git-shims` runs `app git shims` when a Claude Code session starts in a git repository. It is advisory: a conflict (exit 3) does not stop the session.

### Install and check the shims

`bash ${BU_ROOT}/app git shims` puts the shim of each mapped hook into the hooks directory of git. That directory is `core.hooksPath` when it is set, and otherwise the common git directory of the repository, so a worktree shares the hooks of its repository.

| Situation | Result |
|---|---|
| the file is missing, or is an older copy of the shim | copied; reported as `installed` |
| the file is the current shim | reported as `current` |
| a file exists that does not carry the marker | a conflict; the file stays as it is; exit 3 |

`bash ${BU_ROOT}/app git shims --check` reports what is missing or stale and changes nothing. It exits 1 when a shim is missing or stale.

| Exit code | Meaning |
|---|---|
| 0 | every shim is in place |
| 1 | `--check` found a missing or stale shim, or a write failed |
| 3 | a conflict with a foreign hook, a mapped hook without a shim file, or no mapped hook |
| 4 | not inside a repository, or the mapping file is missing |

### Bypass

A git command of the plugin itself does not run the hooks: `commit`, `release`, `promote`, `split` and `pr` pass `core.hooksPath=/dev/null` to their git calls. `pr` says why in its source: the shims call `agentic-os`, which the tool image does not carry, and its checks already ran on the host. Their checks run in the command itself instead (see below).

Do not use `--no-verify` to skip a hook. The commit lint and the minimum check exist to stop a red change before it reaches the pull request.

## Which checks run where

| Check | Local | CI |
|---|---|---|
| commit message (conventional, types, limits) | `app git commit` (lints the message); commit-msg hook; `app git check`; pre-push hook (every commit since the latest tag) | step 2 of `status-checks.yml`, for every commit of the pull request |
| pull request title (with the suffix) | `app git pr`, before the push | step 3 of `status-checks.yml` |
| declared checks of the components | `app git check`; pre-push hook; `app git pr` (every component, refuses a red one); `app git release --apply` (the release gate) | step 4 of `status-checks.yml`, every component |
| rulesets (pull request, squash, linear history, required check; no deletion and no force push on the release and legacy branches) | not checked locally | GitHub enforces them on push and merge |

Two points follow from the table. The local checks run on the commits you have, and CI runs on the head of the pull request, so a green local check does not replace the job. And the rulesets are enforced by GitHub, not by the plugin: a push that the rulesets refuse fails on the server even when every local check passed.

## Related

- [Configuration](git-workflow-configuration.md): `rulesets.yaml` as data, the stage setting, `commitlint.config.mjs` and its limits.
- [Command reference](command-reference.md): the options of `rules-sync`, `shims`, `check` and `pr`.
- [Release and promote](release-and-promote.md): the release and promote paths that the `release` ruleset protects.
- [GitHub App and token service](github-app-and-token-service.md): the App, its permission sets and how the token is issued.
- [Adopting in a project](adopting-in-a-project.md): the order of the steps in a migration.
- [Troubleshooting](troubleshooting.md): a red check, a refused title, a conflicting hook.
