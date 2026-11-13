# Adopting the plugin in a project

A repository joins the git-workflow plugin in one migration. The old release tooling goes: release-please, the backport and split workflows, the commit lint and formatter workflows. The plugin takes over commit lint, release, promote, split and branch rules. The only GitHub workflow left is `status-checks.yml`.

This manual gives the adoption order that the three migrations of edotz repositories proved, then a checklist. The three repositories are worked cases at the end. For the model see [overview.md](overview.md); for every command see [command-reference.md](command-reference.md). When a step fails, look up the symptom in [troubleshooting.md](troubleshooting.md).

## Prerequisites

| Requirement | Why | Check |
|---|---|---|
| agentic-os with the plugin listed in the project | The `app git` commands are modules of the plugin. | `.agentic-os/project.yaml` has a `plugins:` entry with `name: edotz.git-workflow` and its `path`; `bash ${BU_ROOT}/app plugins list` shows it. |
| Docker running | git, `gh`, git-cliff and splitsh-lite run in the tool image. The image is built on the first tool run and is linux/amd64 only. | `docker version` prints a client and a server. |
| `gh` logged in | Pull requests are opened with your own credential. The token service issues App tokens only to members of the organisation. | `gh auth status`. The login was observed with the `repo` and `workflow` scopes; `read:org` was not needed. |
| Active membership of the organisation | The token service refuses a login that is not an active member. | `gh api user/memberships/orgs/edotz --jq .state` prints `active`. |
| `user.name` and `user.email` in git config | The plugin reads the developer identity from git config and stops when a value is unset. | `git config user.name` and `git config user.email` print values. |
| GitHub App `git-workflow-app` installed on the repository | The token service refuses a repository the App is not installed on (`repository not installed`). Every child repository of a split component needs the installation too. | The App's repository selection in the organisation settings lists the repository. |
| Token service reachable | release, promote, split and rules-sync stop without an installation token. The service listens on `127.0.0.1:8790` by default (`TOKEN_SERVICE_PORT`); the commands read `TOKEN_SERVICE_URL` when it is set. | `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8790/token` prints `404`: the service answers only `POST /token`. |
| Node.js and npm in the plugin root | `lint-commit` runs commitlint from the plugin's `node_modules`. | `npm install` in the plugin root; until then `lint-commit` stops with `commitlint is not installed`. |
| pnpm 10 on the host (pnpm workspaces only) | A component declared with `workspace` asks pnpm on the host for its package graph. The tool image has no pnpm. | `pnpm --version` prints 10.x. |

The token service runs where the commands run. A developer on another machine gets no token. The operating model of the service is in [github-app-and-token-service.md](github-app-and-token-service.md).

## Decide the branch roles

Set the roles in the project `.env` before the first `rules-sync`. Do not export them in the shell: a shell export wins over `.env` (see [troubleshooting.md](troubleshooting.md)).

| Variable | Meaning | Default |
|---|---|---|
| `GIT_WORKFLOW_MAIN_BRANCH` | development branch | `master` |
| `GIT_WORKFLOW_RELEASE_BRANCH` | branch that follows release tags, for example `2.x` | none; required for release and rules |
| `GIT_WORKFLOW_LEGACY_BRANCHES` | comma separated old lines, for example `1.x`; unset means no legacy ruleset | unset |
| `GIT_WORKFLOW_APP_ID` | numeric ID of the App; the bypass actor of the rulesets | none; required for `rules-sync --apply` |
| `GIT_WORKFLOW_STAGE` | `development` or `production` | `development` |
| `GIT_WORKFLOW_WORKTREE_DIR` | absolute folder for the worktrees of `app git worktree` | `$HOME/worktrees` |

```bash
bash ${BU_ROOT}/app git workflow-setup validate
```

Expected output: `The branch settings are valid`, then one line for `GIT_WORKFLOW_MAIN_BRANCH` and one for `GIT_WORKFLOW_RELEASE_BRANCH`.

The `development` stage creates a `master` ruleset without rules. Use `production` once pull requests are required on `master`.

## Adoption procedure

The order follows the migrations. Where a step has a reason that is not obvious, the step states it.

### 1. Declare the components

Write `components.yaml` at the repository root. The fields and their rules are in [git-workflow-configuration.md](git-workflow-configuration.md). The short form for the rules that matter here:

- `paths` lists the directories a component owns. `["."]` is the whole repository and is allowed only for one component.
- `version: none` makes a component with no tag and no release. It needs an empty `version_files`.
- `split: yes` needs `owner` and `repo` and `version: yes`. It is refused in a single repository.
- A `composer.json` in `version_files` must hold a `version` key; without one the release stops with `remove it from version_files`.

A single repository declares one component at the root:

```yaml
components:
  - name: my-extension
    paths: ["."]
    version_files: [ext_emconf.php]
```

List `ext_emconf.php` only when the version lives there. That writer takes plain `X.Y.Z` versions, so such a component makes final releases only.

A monorepo declares one entry per component:

```yaml
components:
  - name: collection
    paths: ["packages/collection"]
    version_files: [packages/collection/composer.json]
    checks: ["<the component's own quick check>"]
    split: yes
    owner: edotz
    repo: php-collection
```

Verify with `bash ${BU_ROOT}/app git check`. It prints one result per component and exits 0 when every component is green. An invalid declaration is refused with the errors on screen.

### 2. Add the status check

Copy the plugin's `.github/workflows/status-checks.yml` into the repository, and the plugin's `commitlint.config.mjs` to the repository root. The workflow reads `commitlint.config.mjs` from the repository root, while the local lint reads the plugin's copy. Keep the two equal.

The workflow runs three things: the commit lint of the pull request commits, the pull request title lint, and the checks declared in `components.yaml`. Its job is named `check`; the `master` ruleset of step 5 requires that context.

Do not add a `paths:` filter to the workflow. A required workflow whose path filter matches no changed file never reports `check`, and the pull request stays blocked.

Step 1 and step 2 can go into one pull request. The php-project migration did so.

### 3. Set the branch roles

Set `GIT_WORKFLOW_RELEASE_BRANCH` and, if an old line exists, `GIT_WORKFLOW_LEGACY_BRANCHES` in `.env` as described above. Run `bash ${BU_ROOT}/app git workflow-setup validate` again. The rulesets of step 5 take their branch names from these values.

### 4. Freeze and clean the legacy lines

When the repository has an old line that stays in use (a release branch for an older major version), freeze it before its files are removed:

1. Tag the old head as a legacy tag. The php-project migration used `legacy/1.x-freeze` on the head of `1.x`.
2. Open a pull request into the legacy branch that removes the old workflows and release files from it. The typo3-cms migration removed the release-please and commit lint files from `1.x` with one pull request; the php-project migration removed 47 files.

The legacy ruleset of step 5 covers the legacy branch once `GIT_WORKFLOW_LEGACY_BRANCHES` names it.

### 5. Create the rulesets, then remove classic protection

Run the dry run first, then apply. Use the stage you want for `master`; `production` requires pull requests.

```bash
bash ${BU_ROOT}/app git rules-sync --dry-run --stage production
bash ${BU_ROOT}/app git rules-sync --apply --stage production
```

Expected dry run: `create` for `master` and for the release branch; `skipped` for `legacy` when `GIT_WORKFLOW_LEGACY_BRANCHES` is unset. Run this after the pull request of step 2 has run once, so that the `check` context exists.

The dry run also warns about two things that need your decision:

- `classic protection covers <branch>, required checks: ...`: the branch still has classic branch protection. Remove it through the repository settings or the API, once the rulesets exist, so that the branch is never unprotected. The typo3-cms migration did so.
- `foreign ruleset <id> <name> covers <branch>`: a ruleset that rules-sync does not manage covers the branch. rules-sync never deletes it; the decision is yours.

Verify that the classic protection is gone:

```bash
gh api repos/edotz/<repository>/branches/master/protection
```

Expected: `Branch not protected` (HTTP 404). Do this for every branch the dry run named.

Remove the classic protection before the pull request of step 6 merges. Its required checks name the workflows that step removes, and nothing merges while a required check never reports.

### 6. Remove the old workflows and release files

One pull request on the main branch removes what the plugin replaces. The typical list, from the three migrations:

| Where | Remove (those present) |
|---|---|
| `.github/workflows` | `release-please.yml`, `commit-lint.yml`, `php-cs-fixer.yml`, `merge-split-repo.yml`, `sync-to-monorepo.yml`, `release-pipeline.yml`, `post-release.yml`, `backport.yml` |
| `.github` | `branch-protection.yaml`, `README.md` |
| repository root | `release-please-config.json`, `.release-please-manifest.json` |
| each package (monorepo) | `release-please-config.json`, `.release-please-manifest.json`, `release-pipeline.yml`, `sync-to-monorepo.yml`, `.github/CLAUDE.md`, `.github/branch-protection.yaml` |

Keep `status-checks.yml` in `.github/workflows`. The nodejs-project migration modified its package `release-publish.yml` rather than removing it; a release made with the App starts workflows that listen on `release: published`, so review that file before keeping it.

Verify with `ls .github/workflows`: the only file left is `status-checks.yml`.

### 7. Place the baseline tags

A baseline tag records the version a component was last released as. It is what the plugin counts from.

**Why the position matters.** The next release counts the commits of a component after its latest stable tag, in its paths. A baseline tag on the last commit that touches the component leaves nothing counted, so the released version stays and the next `feat`, `fix`, `perf` or breaking commit makes the next release. A `chore`, `ci`, `docs`, `test`, `style`, `refactor` or `build` commit does not. A baseline tag placed before a commit that touches the component makes that commit count.

**Rules for the tag:**

- The name is `vX.Y.Z` in a single repository and `<component>/vX.Y.Z` in a monorepo. The version is the one the component was last released as.
- Place it on the last commit that touches the component's paths, and only after the commits of steps 4 and 6 are merged. The php-project migration placed its eight tags before the cleanup pull request and had to move them after it.
- Do not place it before the component's directory existed. The split then stops with `no history`.
- The plugin never moves an existing tag. A baseline placed wrongly is corrected by you, after a dry run shows the effect.

Find the commit and create a lightweight tag:

```bash
git log -1 --format=%H -- packages/collection
git tag collection/v2.0.0 <sha-from-the-line-above>
git push origin collection/v2.0.0
```

The tag is pushed with your own git credential. Use `.` in the `git log` path for a single repository.

Verify with the dry run. A baselined component is listed only when a commit after its tag counts:

```bash
bash ${BU_ROOT}/app git release --dry-run
```

Expected: `Nothing to release: no component changed since its latest tag` when nothing counts, or a proposal for the commits after the tag.

### 8. Install the shims and enable the pre-push guard

The shims are the hook files of the plugin. They go into the directory git runs hooks from: `core.hooksPath` when set, otherwise the common git directory, so worktrees share them.

```bash
bash ${BU_ROOT}/app git shims
bash ${BU_ROOT}/app git shims --check
```

Expected after the install: each shim reported `current`; `--check` exits 0. A foreign hook file stays where it is and is reported as a conflict (exit 3); move it aside yourself, then run again.

Installing the shims does not turn the pre-push guard on. Check and enable it:

```bash
bash ${BU_ROOT}/app hooks status
bash ${BU_ROOT}/app hooks enable pre-push minimum-check
```

With the guard on, a push of a commit that is not conventional stops with `commit lint failed` and sends nothing. The sandbox pilot verified this.

### 9. First release

```bash
bash ${BU_ROOT}/app git release --dry-run
```

The dry run prints, per component, the next version, the tag, the files and the notes. Nothing changes.

When the proposal is right, run on the main branch with a clean working tree:

```bash
bash ${BU_ROOT}/app git release --apply
```

Apply makes the release commit `chore(<component>): release <tag>`, the tag, the push and, in a repository of one component, the GitHub Release, all as the App. It refuses a run off the main branch, a dirty tree and a red minimum check. With more than one component no GitHub Release is made: the tags are enough, because the children are what Composer and npm read. Use `--pre <channel>` for a pre-release, for example `--pre rc`; `--draft` leaves the Release of a single component unpublished.

For a split component, send the new release to its child after the release, with `bash ${BU_ROOT}/app git split <component> --apply` (step 11).

### 10. Move the release branch once

The release branch (for example `2.x`) still holds the old line. Its head is not an ancestor of the release commit, so the first move is a baseline, and a fast-forward is refused.

```bash
bash ${BU_ROOT}/app git promote <release-tag> --dry-run
bash ${BU_ROOT}/app git promote <release-tag> --apply --confirm edotz/<repository>
```

The dry run names the divergence. The apply tags the old head `legacy/pre-promote`, then force-pushes the release branch with a lease on that head. Run the baseline once, with `--confirm`.

After the baseline, every promote is a fast-forward and needs no `--confirm`:

```bash
bash ${BU_ROOT}/app git promote <release-tag> --dry-run
bash ${BU_ROOT}/app git promote <release-tag> --apply
```

If the release branch does not exist yet, promote creates it at the commit of the tag. The notes for the nodejs-project do not record a promote of its `1.x`; check with the dry run.

### 11. Children of a monorepo (split components)

Each component with `split: yes` goes to its own child repository. Do this for each child, one child per apply.

1. Make sure the child repository exists and the App is installed on it. Without the installation the token request answers `repository not installed`.
2. The child's default branch must be the main branch of the monorepo, `master`. The split refuses a child whose default branch differs. If the child only has `1.x` or `2.x`, create `master` in it and make it the default first.
3. Dry run. Without a component the dry run covers every split component:

   ```bash
   bash ${BU_ROOT}/app git split <component> --dry-run
   ```

   The dry run prints the split head, the ancestry to the child head and the tree difference. A child that is not a descendant of the split is reported with a warning that it needs a baseline.
4. Apply. A related child gets a fast-forward. An unrelated child needs `--confirm` once:

   ```bash
   bash ${BU_ROOT}/app git split <component> --apply
   bash ${BU_ROOT}/app git split <component> --apply --confirm edotz/<child>
   ```

   The confirm baseline keeps the old head of the child as `legacy/pre-split` and replaces the child's `master` with a lease on that head. The old head is kept; nothing is deleted.
5. Child tags. The component tags (`<component>/vX.Y.Z`) reach the child as `vX.Y.Z`. A child tag that already exists at another commit is skipped with a warning and not moved.
6. Verify. A second apply reports that the child is at the split head and does nothing; it asks for no token.

The apply pushes the split head and the tags of one component only, and only to the main branch of the child.

## Worked cases

### Single package TYPO3 extension

`edotz/typo3-cms`: one component at `.`, release branch `2.x`, legacy line `1.x`.

- The legacy line `1.x` was frozen and cleaned in its own pull request. The legacy ruleset covered `1.x` before classic protection was removed, so the branch was never unprotected.
- Classic protection on `1.x` and `2.x` was removed through the API before the pull request that removed the release-please and commit lint workflows merged. Its required checks named those workflows.
- `2.x` kept its old content and old workflows until the first real release, which made the one-time baseline promote necessary (step 10).

### PHP monorepo with eight split components

`edotz/php-project`: eight components under `packages/<name>` (collection, db, error, log, object, persistence, serializer, utility), each with `version_files: packages/<name>/composer.json`, `split: yes`, `owner: edotz` and `repo: php-<name>`. Its check runs php-cs-fixer on its own path. Release branch `2.x`, legacy `1.x`.

- The declaration, the status check and the removal of the old workflows came first; the legacy line `1.x` was tagged `legacy/1.x-freeze` before its 47 files were removed.
- The old release train in the packages (49 files) was removed in a separate pull request after the first baseline tags. The tags then had to move past that commit, because the commit touched the packages after the tags.
- The rulesets were created with the production stage; classic protection on `master`, `1.x` and `2.x` was removed afterwards.
- Each child got `master` as its default branch before its split, since the split refuses any other default. Eight split baselines ran, one child per run with `--confirm`. Each old head became `legacy/pre-split`. The child tags existed at other commits, so they were skipped with a warning.
- After the eight runs, `release --dry-run` listed nothing: no component had a commit after its tag.

### Node monorepo with ten split components and pnpm

`edotz/nodejs-project`: ten npm packages under the scope `@edotz`, each declared with `workspace: @edotz/<name>`, `split: yes`, `owner: edotz` and `repo: <name>`. Release branch `1.x`; no legacy line.

- The workspace moved from yarn to pnpm first (`packageManager` is `pnpm@10.11.1`; `.npmrc` holds `shamefully-hoist=true`). Workspace components call pnpm on the host, and the tool image has no yarn. In a real clone at the migration commit, `pnpm install --frozen-lockfile` answered `Lockfile is up to date` for all eleven workspace projects and exited 0.
- The migration pull request added `components.yaml` and `status-checks.yml` and removed the old workflows at the root and in each package.
- The App was not installed on two child repositories when their baselines ran. Their token requests answered `repository not installed` until the installation was added.
- One split check failed once with `ls-remote answered with 128`, a transient failure; the rerun passed.
- After ten baselines, a dry run over all components answered that every child was at the split head.

## Checklist

| Check | Command | Expected |
|---|---|---|
| Branch settings valid | `bash ${BU_ROOT}/app git workflow-setup validate` | `The branch settings are valid` and the two branch names |
| No shell override of a setting | `env \| grep GIT_WORKFLOW_` | empty, or values equal to `.env` |
| Plugin listed | `bash ${BU_ROOT}/app plugins list` | a row `edotz.git-workflow` with its path |
| Docker running | `docker version` | client and server versions |
| Token service up | `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8790/token` | `404` |
| Membership active | `gh api user/memberships/orgs/edotz --jq .state` | `active` |
| Components green | `bash ${BU_ROOT}/app git check` | one result per component; exit 0 |
| Shims current | `bash ${BU_ROOT}/app git shims --check` | each shim `current`; exit 0 |
| Pre-push guard on | `bash ${BU_ROOT}/app hooks status` | `pre-push` `minimum-check` enabled |
| Rulesets match | `bash ${BU_ROOT}/app git rules-sync --dry-run --stage production` | no `foreign ruleset` and no `classic protection covers` line |
| Classic protection gone | `gh api repos/edotz/<repository>/branches/<branch>/protection` | `Branch not protected` (HTTP 404), for each branch |
| Old workflows gone | `ls .github/workflows` | only `status-checks.yml` |
| Baselines hold | `bash ${BU_ROOT}/app git release --dry-run` | no proposal for a baselined component unless a counted commit follows its tag |
| Legacy tags present | `git ls-remote --tags origin 'legacy/*'` | the freeze, pre-promote and pre-split tags you created |
| Release branch follows | `bash ${BU_ROOT}/app git promote <release-tag> --dry-run` | names the commit of the tag and no divergence |
| Child at split head | `bash ${BU_ROOT}/app git split <component> --dry-run` | the child at the split head; the apply does nothing |

## What is useful in a consuming project

### Workflow status

```bash
bash ${BU_ROOT}/app git workflow-status
```

Prints JSON: the commits not yet released, per component the latest release tag and the commits since it, the position of the release branch against that tag (on, behind or absent), and the recent workflow runs. The runs are empty without a `gh` login or without network.

### Branch cleanup

```bash
bash ${BU_ROOT}/app git branch-cleanup --dry-run
```

Lists merged, stale and safe-to-delete branches. A squash-merged branch counts as merged: its tree is compared with the base, and a merged pull request with the branch as head counts too, using your `gh` login. Stale means older than `PLUGIN_EDOTZ_GIT_WORKFLOW_STALE_DAYS` (default 30). Flags: `--local-only`, `--remote-only`, `--dry-run`, `--force`. Without `--force` it asks before it deletes.

### Starting a change

```bash
bash ${BU_ROOT}/app git start feat add-login
```

`start` creates the branch `<type>/<name>` from the main branch, switches the checkout to it and prints its name. The type is one of the commit types (`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`). The branch has no upstream.

`start` refuses a branch that exists locally or on origin, and refuses when local `master` differs from `origin/master`. `app git worktree` still manages linked worktrees for those who want one; run `split` and `release` from the main clone, not from a linked worktree: the sandbox pilot recorded a `splitsh-lite failed` there. A linked worktree also needs its own `npm install` for checks that run from `node_modules/.bin`.

### Slash commands in Claude Code

The plugin registers these commands in `commands/commands.yaml`. Each one runs the `app git` command of the same name.

| Command | Argument hint | Use |
|---|---|---|
| `/git:start` | `<type> <name>` | a new branch from the main branch |
| `/git:commit` | `<paths> [--message <text>] [--yes]` | commit the paths named, with a conventional message |
| `/git:check` | `[component]` | the minimum check, before a pull request or a push |
| `/git:pr` | `[--dry-run] [--draft]` | push the branch and open the pull request |
| `/git:release` | `[--dry-run\|--apply] [--draft] [--pre <channel>]` | release the components that changed |
| `/git:promote` | `<tag> [--dry-run\|--apply]` | move the release branch to a release tag |
| `/git:rules-sync` | `[--dry-run\|--apply] [--stage <development\|production>]` | create or update the rulesets |
| `/git:split` | the split arguments of `app git split` | send a component to its child |

A project that enables the plugin gets them as `.claude/commands/git/<name>.md` when the framework compile has run; check the command picker afterwards. `/git:commit` needs `--message` and `--yes` inside Claude Code, because its confirmation reads standard input.

### Add a component later

1. Add the entry to `components.yaml`, with its paths, version files and split settings.
2. A single repository becoming a monorepo: all tags take the prefix `<component>/`. The existing component continues from its latest unprefixed `vX.Y.Z` tag. Old tags stay where they are.
3. If the new component has a released version, place its baseline tag (step 7).
4. If it is a split component, install the App on its child, create the child's `master` as default, and run its first split baseline (step 11).
5. Verify with `bash ${BU_ROOT}/app git check` and `bash ${BU_ROOT}/app git release --dry-run`.

### Change the release branch

1. Set `GIT_WORKFLOW_RELEASE_BRANCH` in `.env`, and run `bash ${BU_ROOT}/app git workflow-setup validate`.
2. Run `bash ${BU_ROOT}/app git rules-sync --dry-run --stage production`, then `--apply`. The `release` ruleset follows the new name.
3. Promote the release tag to the new branch. It is created at the commit of the tag when absent; a diverged branch needs the baseline (step 10).
4. Put the old branch into `GIT_WORKFLOW_LEGACY_BRANCHES` to keep it under the legacy ruleset.

### Retire the plugin from a repository

No command retires the plugin. The steps below are manual. Ask the developer before each destructive one.

1. Stop the release, promote, split and rules-sync runs.
2. Remove the `edotz.git-workflow` entry from the `plugins:` list in `.agentic-os/project.yaml`, then run `bash ${BU_ROOT}/app plugins sync`.
3. Delete the shim files in the git hooks directory that carry the line `# agentic-os-hook:`.
4. Delete the `master`, release and legacy rulesets in the repository settings. No command deletes them. Delete them before the `status-checks.yml` workflow goes; otherwise pull requests wait for a `check` that never reports.
5. Remove `status-checks.yml`, `components.yaml` and `commitlint.config.mjs` in a pull request.
6. Keep the tags. They are the history of the released versions.
