# Reference: release, promote and split

Run every command as `bash ${BU_ROOT}/app git <command>`. The rules of the skill body hold in
every step below.

## Read before a release

- Read the two branch settings: `workflow-setup validate`.
- Read what is unreleased: `workflow-status`, or `git log <latest tag>..HEAD -- <component paths>`.
- A commit releases a component when its type is `feat`, `fix`, `perf` or breaking (`!` after the
  type, or a `BREAKING CHANGE` footer) and it changes a file under a path of the component.
- `chore`, `ci`, `docs`, `test`, `style`, `refactor` and `build` commits release only when they
  are marked breaking.
- A non-conventional commit after the latest tag keeps `check` red until a tag follows it.

## Read the release dry run

The dry run changes nothing and exits 0 when it can plan.

| Output | Meaning | Next step |
|---|---|---|
| a version, a tag, files and notes per component | a release is proposed | list them for the developer |
| `Nothing to release` | no releasing commit after the latest stable tag | find a real change |
| `pending — <tag> is HEAD` | the tag is on `HEAD` already | ask what the tag is, see below |

- A pending tag after a migration is a baseline tag: it marks a version released before the
  plugin, and the apply would only push the tag and create its GitHub Release.
- A pending tag after an interrupted apply needs the apply: it pushes the tag and creates the
  GitHub Release, with no new commit.
- Ask the developer which case it is before the apply.

## Apply a release

- Refused with exit 1: the current branch is not the main branch, the working tree is dirty, or
  the minimum check is red.
- Refused with exit 3: `user.name` or `user.email` is unset, or a version file is refused.
- Needs: Docker and the token service.
- Effect, per component: the version files and `CHANGELOG.md`, the release commit
  `chore(<component>): release <tag>` on the main branch, the tag and the GitHub Release, all as
  the App.
- Variants: `--pre <channel>` with a lower case channel such as `rc`; `--draft` leaves the GitHub
  Release unpublished.
- A wrong release is corrected by a new release.

## Before a promote

- Promote accepts a tag whose commit is `chore(<component>): release <tag>`; a baseline tag or a
  hand made tag is refused.
- Nothing to do when both branch settings are `master`, or when the release branch is at the tag.
- Dry run first: it prints the commit and the release branch position.
- Fast forward: `promote <tag> --apply`.
- Baseline mode applies when the release branch is not an ancestor of the release commit. The dry
  run then prints the divergence and exits 1; that is the expected answer, not a failure.
- Baseline apply: `promote <tag> --apply --confirm <owner/repo>`. The old head of the release
  branch is kept as the tag `legacy/pre-promote`, and the branch is moved with a lease.
- An older tag than the release branch position is also baseline mode and moves the branch
  backwards: confirm with the developer that this is the intent.
- Baseline mode for a first migration happens once per repository, after the first real release.

## No backport

- A release is made on the main branch only, and promote moves the release branch to a release tag.
- A fix reaches the release branch through a pull request, a release and a promote.
- Every unreleased `feat`, `fix` and `perf` commit on the main branch ships with that release.
- Show the developer the dry run when the main branch holds features that must not reach
  production; the choice is to ship them with the fix or to wait.

## Split

- Applies to components with `split: yes` in `components.yaml`; it needs two or more versioned
  components.
- Dry run: `split [component]` prints the split head, the ancestry to the child head and the tree
  difference; the apply takes exactly one component.
- Apply: `split <component> --apply`, with the App installed on the child repository.
- Replace a child that does not descend from the split: `--confirm <owner/child>`; the old head
  is kept as the tag `legacy/pre-split`.
- A child tag at another commit is skipped with a warning and never moved.
- A child whose default branch differs from the main branch is refused.
- Only the first path of a component is split.

## Rulesets and shims

- `rules-sync` is a dry run by default; `--apply` creates or updates the rulesets as the App
  and takes `--stage development|production`.
- `shims` installs the commit-msg and pre-push shims; `shims --check` reports and changes nothing.
