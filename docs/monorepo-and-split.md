# Monorepo and split

This manual covers repositories with several components, the components that have their own child repository, and the split that sends their history to the child. For the release itself see [Release and promote](release-and-promote.md).

A repository with one component at the root is a single repository. It cannot split: `split: yes` is refused there.

## Components with several paths

A component names the directories it covers in `paths`:

```yaml
components:
  - name: web
    paths: [apps/web, packages/ui]
    version_files: [apps/web/package.json]
    split: yes
    owner: edotz
    repo: web
  - name: lib
    paths: [packages/lib]
    version_files: [packages/lib/package.json]
    split: yes
    owner: edotz
    repo: lib
  - name: infra
    paths: [infra]
    version: none
```

| Rule | Why |
|---|---|
| The first path is the component's home. Its `CHANGELOG.md` and `README.md` are written there, and it is the root of the child repository. | The split takes one directory as the child root. |
| Only the first path is split. Every other path counts for change detection only. | The split refuses two prefixes that land in the same directory, and the other paths are not part of the child. |
| A path shared by two components counts for both. | A change in shared code releases every component that uses it. |
| A `workspace` component (pnpm) takes its paths from the workspace graph. The package directory comes first, so it is the child root. | `component_paths` lists the package first. |
| `paths: ["."]` is refused for a split component: the whole repository has nothing to split from. | A child must be a directory of the monorepo. |

Put the files of a component that will be split into one directory. The pilot monorepo of the plugin had its component at the repository root and moved the files into `web/` before the split could work.

## Declaring a child repository

For a component with `split: yes`, `components.yaml` needs these fields. The validation of `component_load` refuses the file when a rule is broken, before any command runs.

| Field | Required | Rule |
|---|---|---|
| `split` | optional, default `no` | `yes` or `no` |
| `owner` | with `split: yes` | the owner (user or organisation) of the child repository |
| `repo` | with `split: yes` | the name of the child repository |
| `host` | optional, default `github.com` | the host of the child |

Also required with `split: yes`: `version: yes` (the child receives the component's tags), and at least two components in the file (`split: yes` is refused in a single repository).

`owner`, `repo` and `host` are refused unless `split` is `yes`.

The child URL is built from these fields as `https://<host>/<owner>/<repo>.git`. For the component `web` above it is `https://github.com/edotz/web.git`.

## How split works

The split uses splitsh-lite, which runs in the Docker tool image. It takes the first path of the component and builds the history of that directory: every commit that touches it, with the paths rewritten so that the directory becomes the root.

| Item | What the split does |
|---|---|
| Split head | the split of the commit `HEAD` of the monorepo. The apply and the dry run both use it. Run the command on the commit that the child should get. |
| Branch | the child gets the split head on `GIT_WORKFLOW_MAIN_BRANCH` (default `master`). The child has no branch setting of its own. |
| Tags | every local tag `<component>/v<version>` is pushed to the child as `v<version>`, at the split of the commit the tag names. Pre-release tags are included. |
| Other refs | none. The child receives the branch and the component tags only. |

A component's tag whose commit has no history for its first path stops the split before anything is pushed (see [Baselining](#baselining-existing-child-repositories)).

The tool image has no git in a linked worktree. Run split from the main clone of the repository, not from a linked worktree; from a worktree the command fails with `splitsh-lite failed`.

## Dry run

```bash
bash ${BU_ROOT}/app git split --dry-run
bash ${BU_ROOT}/app git split web --dry-run
```

Without a name, the dry run goes through every component in `components.yaml`. A component with `split: no` is listed as skipped. The dry run reads each child with the developer's own `gh` credential, so the developer needs read access to the child. It changes nothing, on the child or in the tree.

Output for a child that is behind the split (the fixture of `tests/git-split/dry-run.sh`):

```text

[split web]
   child — https://github.com/edotz/web.git
   split head — <split>
   child head — <child>
   ancestry — the child head is an ancestor of the split head: a fast-forward
   tree difference — 2 file(s)
  A <file>
  M <file>
```

The tree difference lists one line per file: a status letter (`A` only in the split, `D` only in the child, `M` changed), a tab and the path. The fixture asserts the words `fast-forward` and the added file.

The ancestry line decides what the apply does:

| Dry run says | Meaning | Apply |
|---|---|---|
| `the child is at the split head already: nothing to apply` | equal | no push, unless a component tag is missing on the child |
| `the child head is an ancestor of the split head: a fast-forward` | the child lags behind | pushes the new head and the tags, without force |
| `the histories diverged` | the child has commits the split does not have | baseline: needs `--confirm` |
| `the child is unrelated to the split: it needs a baseline` | no common history | baseline: needs `--confirm` |
| `<branch> is absent on the child: the apply creates it` | an empty or new child | creates the branch and pushes the tags |

A failed read of the child is reported as `failed read of <url>`. It is different from an absent branch, and the dry run counts it as a failure (exit 1 at the end).

## Apply

```bash
bash ${BU_ROOT}/app git split <component> --apply [--confirm <owner/repo>]
```

Give exactly one of `--dry-run` and `--apply`. `--apply` takes one component name: one child per run. Without a name it stops with exit 2 and pushes nothing.

What the apply does for one component:

1. Refuse a component with `split: no` (exit 2). Refuse `--confirm` with another name than the child (exit 2).
2. Read the child's default branch with the developer's credential. If it is not `GIT_WORKFLOW_MAIN_BRANCH`, refuse with exit 3 and push nothing.
3. Read the child's branch and its tags. A child that does not descend from the split is a baseline case: refuse without `--confirm` (exit 2).
4. Compare the child's tags with the component's local tags. Each local tag `<component>/vX.Y.Z` maps to `vX.Y.Z`:
   - the child has the tag at the same commit: nothing to do, no warning;
   - the child has the tag at another commit: a warning and the tag is left where it is (see [Child tags](#child-tags));
   - the child lacks the tag: it is pushed.
5. When nothing is missing and the child is at the split head, print `nothing to apply` and stop. No token is fetched.
6. Fetch one installation token for the `split` set.
7. In a baseline case, push the child's old head to `legacy/pre-split` on the child.
8. Push the branch and the tags to the child in one atomic push. A baseline uses a lease on the old head.

Output for a fast-forward apply:

```text

[split web (apply)]
   child — https://github.com/edotz/web.git
   split head — <split>
  ✓ split — edotz/web master is at <split>, 2 ref(s) pushed
```

Refusals and their exit codes:

| Condition | Exit | Output starts with |
|---|---|---|
| no name with `--apply` | 2 | `split: --apply takes the name of one component, one child per run` |
| component has `split: no` | 2 | `split: the component ... has split no` |
| `--confirm` names another repository | 2 | `split: --confirm names ...` |
| baseline without `--confirm` | 2 | `split: <owner/repo> does not descend from the split` |
| child default branch differs from `GIT_WORKFLOW_MAIN_BRANCH` | 3 | `split: the default branch of ... is ... but GIT_WORKFLOW_MAIN_BRANCH is ...: nothing was pushed` |
| unknown component name | 4 | `split: component '...' is not declared` |
| failed read of the child | 1 | `split: failed read of <url>` |

Each refusal before the token request pushes nothing and fetches no token. The tests check that the baseline refusal counts zero token requests.

## Baselining existing child repositories

A child that already holds history from an older release train, or an empty child with other history, does not descend from the split. The first apply has to replace its branch. The plugin does this only with the confirmation, and keeps the old head.

Order of work for each existing child:

1. Set the component's baseline tag on the last commit of the monorepo that touches the component (see [Release and promote](release-and-promote.md#the-range)). The tag must sit on a commit where the component's first path has history: a tag on a commit before the directory existed stops the split for that component with `splitsh-lite printed no commit ... the paths have no history`.
2. Make the child's default branch the monorepo's `GIT_WORKFLOW_MAIN_BRANCH`. The plugin does not change the default branch of a repository. If the child's default is another branch (for example `1.x` or `2.x`), the apply refuses with exit 3. Create the branch in the child and set it as default in the repository settings.
3. Install the GitHub App on the child, for the repository. When the App is not installed there, the token service answers `repository not installed (HTTP 404)`.
4. Run the dry run for the child. A baseline is reported as `unrelated` or `diverged`.
5. Apply for that child only, with the confirmation of its name:

   ```bash
   bash ${BU_ROOT}/app git split lib --apply --confirm edotz/lib
   ```

6. Run the dry run again. It must say `the child is at the split head already`.
7. Go on with the next child, one run each.

Output of the baseline apply, for a child that is unrelated to the split:

```text

[split lib (apply)]
   child — https://github.com/edotz/lib.git
   split head — <split>
  ✓ legacy/pre-split — the old head <old> of edotz/lib is kept
  ✓ split — edotz/lib master is at <split>, 3 ref(s) pushed
```

The old head is kept as the tag `legacy/pre-split` on the child. If that tag already exists at another commit, the push fails and the command asks you to delete or rename it on the child, then run again.

A baseline runs once per child. A second apply finds the child at the split head and does nothing.

The tests `tests/git-split/apply.sh` cover: an unrelated child refused without `--confirm`, refused with the wrong name, replaced with `--confirm`, and the old head kept as `legacy/pre-split`.

## Child tags

The rule for component tags on a child:

| Child has the tag `vX.Y.Z` | Apply does |
|---|---|
| at the split of the same commit | nothing, silently |
| at another commit | prints `! tag vX.Y.Z — skipped: <owner/repo> has it at <a>, the split of <component>/vX.Y.Z is <b>: it is not moved`, leaves the child tag, pushes the rest, exits 0 |
| not at all | pushes it |
| an annotated tag at the right commit | counts as the same commit; not blocked |

A child tag is never moved or deleted. This matters in children that were released by the old train: their `vX.Y.Z` tags may sit on other commits, and the split warns about each one. The component's release still happens in the monorepo, under its own tag.

## Permission set

The apply pushes with an installation token of the App for the `split` set. The set is defined in `bin/config/token-service.json`:

| Set | Permissions |
|---|---|
| `split` | `contents: write`, `workflows: write` |

The token is for the child repository only. `workflows: write` is in the set so that a split that changes files under `.github/workflows` can be pushed. The App holds `workflows: write`, but the token service narrows every token to the set of its command, so a push of workflow files works only with this set. After a change of `token-service.json` the service image has to be rebuilt, because the image holds the file. If a split that changes a workflow file is refused by GitHub, check the App permissions and the service image; see [GitHub App and token service](github-app-and-token-service.md).

The dry run needs no App token. It reads the child with the developer's `gh` login.

## After the split: what a child repository looks like

| Item | State |
|---|---|
| Default branch | the monorepo's `GIT_WORKFLOW_MAIN_BRANCH` |
| Branch content | the split tree of the component's first path: the component's files at the root, its version file with the version the release wrote, its `CHANGELOG.md` and `README.md` |
| Tags | `vX.Y.Z` for each release of the component, on split commits; plus `legacy/pre-split` after a baseline |
| GitHub Releases | none. The split creates none; the releases are in the monorepo under `<component>/vX.Y.Z` |
| Edits | none. The child is write-only: it receives the split and nothing else |

A commit made in the child is not in the split history. The next apply sees a child that does not descend from the split, refuses it without `--confirm`, and with `--confirm` replaces the branch. The child commit is kept only as `legacy/pre-split`. So any change to a child belongs in the monorepo, in the component's paths.

The migrations removed the old release automation from the children (release-please configuration, the sync-to-monorepo workflow, the release PRs). A child should carry no workflow that makes its own versions or tags, because the plugin no longer does that there. A workflow that publishes a package on a tag `v*` is the consumer's, and it runs on the tag the split pushes.

Whether the children carry rulesets or branch protection of their own is not verified; `rules-sync` configures the rulesets of the repository it runs in.

## Lessons of the pilot and the migrations

| Situation | What happened | What to do |
|---|---|---|
| component at the repository root (`paths: ["."]`) | cannot be split | move the files into a directory, then declare that directory |
| baseline tag on a commit before the component's directory existed | the apply stopped: `splitsh-lite printed no commit`, nothing pushed | move the tag to the last commit that touches the component, or delete it if it was made by mistake |
| baseline tags on a project-tier commit that touches no component | every component counted its whole history and the dry run proposed `3.0.0` for all of them | place each tag on the last commit that touches its component |
| child default branch `1.x` or `2.x` | refused with exit 3 | create `master` in the child, set it as default, then apply |
| App not installed on the child | token request refused with `repository not installed (HTTP 404)` | install the App on that repository, then apply |
| child tag already at an older commit | warning `skipped`, the child tag stayed | nothing to undo; the child keeps its tag, the monorepo's release tags go on the new commits |
| split from a linked worktree | `splitsh-lite failed` | run from the main clone |
| one push interrupted after the release commit | the commit and the tag stayed local | rerun the release apply; the component is pending and the rerun finishes the push |
