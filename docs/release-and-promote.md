# Release and promote

This manual covers how the plugin decides a version, how `app git release` makes the release commit, tag and GitHub Release, and how `app git promote` moves the release branch to a release. For the monorepo split to child repositories see [Monorepo and split](monorepo-and-split.md). For the command options see [Command reference](command-reference.md).

## The common path

1. Merge the changes of a component into `master` through pull requests (see [Daily loop](daily-loop.md)).
2. Run the dry run and read the proposal:

   ```bash
   bash ${BU_ROOT}/app git release --dry-run
   ```

3. Apply it. This makes the release commit, the tag, the push and, in a repository of one component, the GitHub Release:

   ```bash
   bash ${BU_ROOT}/app git release --apply
   ```

4. If the repository has a release branch, move it to the release:

   ```bash
   bash ${BU_ROOT}/app git promote v1.1.0 --dry-run
   bash ${BU_ROOT}/app git promote v1.1.0 --apply
   ```

The dry run changes nothing. The apply runs on `master` only, with a clean working tree.

## How a version is decided

### Which commits count

The plugin reads the conventional commit subjects of the commits that touch a component's paths. Only these types make a release:

| Commit | Bump | Notes |
|---|---|---|
| `feat` | minor | `1.0.0` becomes `1.1.0` |
| `fix` | patch | `1.0.0` becomes `1.0.1` |
| `perf` | patch | `1.0.0` becomes `1.0.1` |
| breaking (`!` after the type, or a `BREAKING CHANGE` footer) | major | `refactor(a)!: ...` and a `chore` with a `BREAKING CHANGE` footer both give `2.0.0` from `1.x` |

These types do not release, even in a component path: `chore`, `ci`, `docs`, `test`, `style`, `refactor` and `build`. They are also left out of the release notes. The rule lives in `bin/config/cliff.toml`.

A commit touches a component when it changes a file under one of the component's `paths`. A commit that changes two components counts for both. A `feat` in another component's path does not release this one.

### The range

The base version is counted from the commits after the latest stable tag of the component, the tag that matches `vX.Y.Z` (or `<name>/vX.Y.Z`) and is reachable from `HEAD`. Pre-release tags are ignored for the base. The place of the tag does not matter, only the commits after it do.

The baseline tag (see [Monorepo and split](monorepo-and-split.md#baselining-existing-child-repositories)) marks the version that was already released before the plugin took over. It sits on the last commit that touches the component, because the commits after it are the ones still to be released.

A component without any tag counts its whole history.

### No commit means no release

If no `feat`, `fix`, `perf` or breaking commit of the component lies after its latest stable tag, the component is not released. The dry run then prints `Nothing to release` for it (see [When nothing is proposed](#when-nothing-is-proposed)).

### Pre-release channels

`--pre <channel>` makes a pre-release line. The channel is lower case letters, for example `alpha`, `beta` or `rc`.

| State | Without `--pre` | With `--pre rc` |
|---|---|---|
| Stable tag `v1.0.0`, one `feat` after it | `v1.1.0` | `v1.1.0-rc.1` |
| Tag `v1.1.0-rc.1`, one `fix` after it | `v1.1.0` | `v1.1.0-rc.2` |

The final release after a pre-release counts from the older stable tag, so it is `v1.1.0` and the pre-release tag does not change the base. A tag of any kind on `HEAD` makes the component pending when `--pre` is given (see [The pending case](#the-pending-case)). The pre-release is a GitHub Release marked as pre-release. The tests cover the rc cases; the other channels follow the same code path.

`ext_emconf.php` takes plain `X.Y.Z` only, so a pre-release is refused for a component that lists it (see the table below).

### Version files

`version_files` in `components.yaml` lists the files whose version the release commit writes. The writer is chosen by the file name. Every listed file is checked before any file is written, so a refusal leaves every file untouched.

| File name | What the release writes | Refused when |
|---|---|---|
| `package.json` | the `version` key | never |
| `composer.json` | the `version` key | the file has no `version` key. Composer reads the tag, so remove the file from `version_files` (configuration error, exit 3) |
| `ext_emconf.php` | the one `'version' => '...'` line, every other byte kept | the version is a pre-release, or the file does not hold exactly one `'version'` line (exit 3) |
| any other name | nothing | always: configuration error, exit 3 (for example `pnpm-lock.yaml`) |

A missing file stops the release with exit 4. After each write the file is read back and must hold the new version.

The release also writes `CHANGELOG.md` and `README.md` in the component's home directory, the first path of the component. These two files are not listed in `version_files`.

## The release command

```bash
bash ${BU_ROOT}/app git release (--dry-run | --apply) [--draft] [--pre <channel>]
```

Give exactly one of `--dry-run` and `--apply`; otherwise the command stops with exit 2.

### Dry run

The dry run runs the minimum check and prints, per component, the next version, the tag, the files and the notes. It changes nothing. It needs Docker, because git-cliff runs in the tool image.

Output layout (the notes are git-cliff output, shown here as `...`):

```text

[release object]
   version — 1.1.0
   tag — v1.1.0
   files — package.json, CHANGELOG.md, README.md
...
```

| Line | Meaning |
|---|---|
| `[release <name>]` | a component that gets a release commit |
| `version` | the version the release writes |
| `tag` | the tag the release creates; `v<version>` in a single repository, `<name>/v<version>` in a monorepo |
| `files` | the `version_files` of the component, then `CHANGELOG.md` and `README.md` of its home directory |
| notes | the release notes: a section for the version with its commits, without the header |
| `pending` | the component's tag is already on `HEAD` (see [The pending case](#the-pending-case)) |

If a component has nothing to release and no pending tag, it is not listed.

### Apply, step by step

The apply runs per component, in the order of `components.yaml`. A component is finished before the next one starts.

1. Refuse unless the current branch is the main branch (`GIT_WORKFLOW_MAIN_BRANCH`, default `master`) and the working tree is clean. Nothing is changed when this fails.
2. Read the remote `origin`, which must be a github.com repository, and the developer's `user.name` and `user.email`. The release commit is made with that identity.
3. Fetch one installation token of the GitHub App for the `contents` set (see [Tokens and where things go](#tokens-and-where-things-go)).
4. For each component to release:
   1. Write the version into the `version_files`.
   2. Prepend the release notes to `CHANGELOG.md` (created when missing).
   3. Rewrite the lines between the README markers, when the README has them (see below).
   4. Commit the files as `chore(<name>): release <tag>`, with the hooks of the repository switched off. If the commit fails, the files are restored.
   5. Create the tag `<tag>` on the release commit.
   6. Push `HEAD` to the main branch and the tag to `origin`, as the App.
   7. Create the GitHub Release of the tag, when it does not exist and the repository has one component. Its notes are generated from the tag, not from the dry run. A repository of several components makes none and prints `skipped`.
5. For each pending component: push the tag and, in a repository of one component, create its GitHub Release when missing.
6. Drop the token.

Commit subjects the release writes, with the names of the example repositories:

| Repository | Release commit subject | Tag |
|---|---|---|
| single, component `object` | `chore(object): release v1.1.0` | `v1.1.0` |
| monorepo, component `api` | `chore(api): release api/v1.1.0` | `api/v1.1.0` |

The README markers are the two lines `<!-- release:start -->` and `<!-- release:end -->`. Between them the release writes `Version <version>` and a link to the GitHub Release. A README without both markers, or a missing README, is left alone and the output says so.

The GitHub Release is created with the tag as title. A pre-release version creates a pre-release. `--draft` leaves it unpublished. When the repository has more than one component, the release is created with `--latest=false`, so that `releases/latest` is not moved by one component.

### Options

| Option | Effect |
|---|---|
| `--dry-run` | print the proposal, change nothing |
| `--apply` | make the release, as described above |
| `--pre <channel>` | release a pre-release of this channel (lower case letters) |
| `--draft` | create the GitHub Release as a draft for a person to publish. The tag is still pushed. No effect in a repository of several components. Not covered by the tests |

### Tokens and where things go

| Step | Credential | Token set |
|---|---|---|
| dry run | none, reads local history only | none |
| release commit, push of `master` and the tag, GitHub Release | installation token of `git-workflow-app` | `contents` |

The push goes to `origin` on github.com over HTTPS. The release commit is pushed straight to `master`. The `master` ruleset requires a pull request, but the App is the bypass actor of that ruleset, so the push passes. This is why a release commit does not show up as a pull request. See [Rulesets and CI](rulesets-and-ci.md) and [GitHub App and token service](github-app-and-token-service.md).

### The pending case

A component is pending when its tag is on `HEAD` already. This happens after a baseline tag placed on the head of `master`, and after an apply that was interrupted after its commit and tag but before the push or, in a repository of one component, the GitHub Release.

```text
[release object]
   pending — v1.0.0 is HEAD: apply makes sure the tag is pushed and the GitHub Release exists
```

The apply of a pending component pushes the tag and creates the GitHub Release when it is missing. It makes no new commit and no new version. When both exist, the apply prints that the GitHub Release exists and finishes. A repository of several components prints `apply makes sure the tag is pushed` and makes no GitHub Release.

With `--pre`, a tag of any kind on `HEAD` makes the component pending, so a pre-release on `HEAD` does not stop the final release from being proposed. Without `--pre`, only a stable tag on `HEAD` makes it pending.

After an interrupted apply, run the apply again. The pilot of the plugin stopped the push after the release commit and the tag were made; the tree was clean and the second apply found the tag pending and finished the push and the GitHub Release.

### Multi-component releases

Each component that changed gets its own release commit and tag, and in a repository of one component its GitHub Release, one after the other, in the order of `components.yaml`. If two components changed in one commit, both are released. Their release commits follow each other on `master`.

The minimum check runs for every component to release before anything is written. One red component refuses the whole release and nothing is changed.

## Worked example: single-component repository

The repository has one component `object` at the root, with `paths: ["."]` and `version_files: [package.json]`. The last tag is `v1.0.0`. Since that tag, one `feat` has been merged to `master`.

Dry run:

```bash
bash ${BU_ROOT}/app git release --dry-run
```

Expected output, from the layout above: a `[release object]` section with `version — 1.1.0`, `tag — v1.1.0` and `files — package.json, CHANGELOG.md, README.md`. The notes list the `feat` commit under a Features group. The fixture of the test `tests/git-release/dry-run.sh` asserts the version, the tag, the file and the notes text; the exact notes depend on git-cliff.

Apply:

```bash
bash ${BU_ROOT}/app git release --apply
```

Result on `master`: one commit `chore(object): release v1.1.0` that changes `package.json`, `CHANGELOG.md` and, when it has the markers, `README.md`. Tag `v1.1.0` on that commit. A GitHub Release `v1.1.0`, not a pre-release.

Run the apply again: the tag is on `HEAD`, so the component is pending and the apply prints that the GitHub Release exists. Nothing new is made.

Promote, when the repository has a release branch `release` (set in `.env` as `GIT_WORKFLOW_RELEASE_BRANCH=release`):

```bash
bash ${BU_ROOT}/app git promote v1.1.0 --dry-run
bash ${BU_ROOT}/app git promote v1.1.0 --apply
```

## Worked example: monorepo

The repository has two components with their own paths and version files:

```yaml
components:
  - name: api
    paths: [api]
    version_files: [api/package.json]
  - name: web
    paths: [web]
    version_files: [web/package.json]
```

Tags so far: `api/v1.0.0` and `web/v2.0.0`. Since then, a `feat` in `api/` and a `fix` in `web/` were merged, in separate commits.

Dry run:

```bash
bash ${BU_ROOT}/app git release --dry-run
```

Expected output, as the test `tests/git-release/multi.sh` asserts it: a `[release api]` section with `version — 1.1.0` and `tag — api/v1.1.0`, and a `[release web]` section with `version — 2.0.1` and `tag — web/v2.0.1`. The files are `api/package.json, api/CHANGELOG.md, api/README.md` and `web/package.json, web/CHANGELOG.md, web/README.md`.

Apply:

```bash
bash ${BU_ROOT}/app git release --apply
```

Result on `master`: `chore(api): release api/v1.1.0`, then `chore(web): release web/v2.0.1`, each with its tag. No GitHub Release is made: a repository of several components has none, and the child repositories carry the tags that Composer or npm read.

Then, when the repository has a release branch, promote the release that should go live. The release branch is one branch for the repository, so promote one tag at a time, the newest first:

```bash
bash ${BU_ROOT}/app git promote web/v2.0.1 --dry-run
bash ${BU_ROOT}/app git promote web/v2.0.1 --apply
```

## When nothing is proposed

The dry run prints this and exits 0:

```text
Nothing to release: no component changed since its latest tag
```

Look at the cause in this order:

| Cause | What it looks like | What to do |
|---|---|---|
| Only `chore`, `ci`, `docs`, `test`, `style`, `refactor` or `build` commits in the component's paths since the latest tag | `git log <tag>..HEAD -- <path>` shows commits, none of them a `feat`, `fix`, `perf` or breaking commit | nothing. These commits release nothing by design. Do not relabel merged commits; the next `feat` or `fix` releases them together |
| A `feat` or `fix` in another component's path | the component's own paths have no releasable commit | nothing; the other component releases |
| The baseline tag sits on `HEAD` | the dry run prints `pending` instead, not nothing | run the apply: it pushes the tag and, in a repository of one component, creates the GitHub Release |
| A baseline tag sits on an earlier commit than the component's last change | the commits after the tag are counted, so work already released may be proposed again | move the baseline tag to the last commit that touches the component, before the first release is made |
| A non-conventional subject since the latest tag | the minimum check is red and the dry run fails with `minimum check is red` | the check lints every commit since the latest tag, so a new commit does not clear it. See [Troubleshooting](troubleshooting.md) |

Do not work around the empty proposal by editing `version_files` or by adding a tag by hand. A hand-made tag on a commit that is not a release commit is not a release: promote refuses it.

## Promote

`app git promote <tag>` moves the release branch to the commit of a release tag. The release branch is `GIT_WORKFLOW_RELEASE_BRANCH` (see [Configuration](git-workflow-configuration.md)). If it equals the main branch, the command prints `nothing to promote` and stops.

```bash
bash ${BU_ROOT}/app git promote <tag> --dry-run
bash ${BU_ROOT}/app git promote <tag> --apply [--confirm <owner/repo>]
```

The tag must be a release tag: its commit's subject must read `chore(<component>): release <tag>`. Any other tag is refused, including a baseline tag placed on an ordinary commit.

The release branch is never moved to the head of `master`. It only follows release commits.

### Fast-forward case

The release branch is an ancestor of the release commit, or it does not exist yet. This is the normal case.

Dry run (the release branch is `release`, at `<old>`, and `v1.1.0` is at `<new>`):

```text

[promote v1.1.0]
   commit — <new>
   release branch — release, now <old>, based on the last fetch
```

The dry run reads the last fetch of the release branch and moves nothing. The apply fetches the branch again before it decides, so a branch that moved on the remote is seen.

Apply:

```text
  ✓ promote — release moved to v1.1.0 (<new>)
```

The push is a fast-forward, made as the App with the `contents` set. It needs no `--confirm`. If the release branch does not exist, the apply creates it at the commit of the tag. If the release branch is already at the tag, the command prints `release is at v1.1.0 already: nothing to promote`.

The branch only moves forward. A tag whose commit is older than the commit the release branch is at is not a fast-forward: the branch is ahead of it, so the command classes it as the baseline case below and needs `--confirm`. The tests cover the forward and the baseline cases; this reverse case follows from the ancestor check in the code and is not tested.

### Baseline case

The release branch exists but is not an ancestor of the release commit. This happens on the first move after a migration, when the branch still carries the history of the old release train.

Dry run: it names the divergence and stops with an error, nothing is moved:

```text
[promote v1.0.0]
   commit — <new>
   release branch — release, now <old>, based on the last fetch
  ! divergence — release is not an ancestor of v1.0.0: the apply keeps its old head as legacy/pre-promote and replaces release
```

Apply without `--confirm`: refused with exit 2 before any token is fetched. The message asks for `--apply --confirm <owner/repo>`.

Apply with the confirmation:

```bash
bash ${BU_ROOT}/app git promote v1.0.0 --apply --confirm owner/repo
```

The steps:

1. Check that `--confirm` names the repository of `origin`. Another name is refused with exit 2.
2. Fetch one installation token for the `contents` set and fetch the release branch.
3. Push the old head to the tag `legacy/pre-promote`. If that tag exists at another commit, the push fails and the command asks you to delete or rename the tag on the remote first.
4. Push the release commit to the release branch with a lease on the old head, so the branch is replaced only if it is still at the old head.

Output:

```text
  ✓ legacy/pre-promote — the old head <old> of release is kept
  ✓ promote — release moved to v1.0.0 (<new>)
```

The old head is still reachable through `legacy/pre-promote`. A second apply prints `nothing to promote`.

### What protects the release branch

The `release` ruleset (from `bin/config/rulesets.yaml`, created by `app git rules-sync`) has four rules: a pull request requirement, linear history, no deletion and no non-fast-forward. The App is the only bypass actor. A developer push to the release branch is therefore refused, and only `promote` moves it. The baseline case replaces the branch, which is a non-fast-forward; it works only because the App bypasses the ruleset and the lease names the old head. The tests do not prove the developer refusal; see [Rulesets and CI](rulesets-and-ci.md).

Never push the release branch by hand, and never force it. The lease and the `legacy/pre-promote` tag are the only safe way to replace it.

## No backport

A release is made on the main branch only, and `promote` moves the release branch to the release commit of a tag, never to anything else. There is no flow that applies one fix to the release branch alone:

1. The fix reaches the main branch through a pull request.
2. `app git release` releases it, together with every other unreleased `feat`, `fix` and `perf` commit on the main branch.
3. `app git promote <tag>` moves the release branch to that release.

When the main branch holds unreleased features that must not reach production yet, the dry run of the release shows them. The choice is then to ship them with the fix, or to wait; a hand-made tag or a cherry-pick onto the release branch is not an option, because `promote` accepts only a tag whose commit is a release commit.

## What a release does not do

- It does not publish packages. Packages (npm, Composer) are the consumer's workflows. The App has no packages permission.
- It does not move the release branch. That is `promote`.
- It does not release a component whose paths did not change, and it does not bump another component's version files.
- It does not run the component's checks beyond the minimum check (commit lint since the latest tag plus the `checks` of the component).
- It does not write to child repositories. That is [split](monorepo-and-split.md).
- It does not open a pull request, and it does not touch feature branches.
- It does not rewrite history, delete tags or move an existing tag.
- It does not use an LLM. The bump and the notes come from git-cliff.
- It does not write a changelog or README beyond the component's home directory and the markers.
