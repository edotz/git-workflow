# Playbook: release, promote and split

Run every command as `bash ${BU_ROOT}/app git <command>`. Every `--apply` and `--confirm` is
preceded by its dry run, and the developer's go comes after you state what the apply pushes, tags
or publishes.

## Before a release

- Read the two branch settings first: `workflow-setup validate`.
- Read what is unreleased: `workflow-status`, or `git log <latest tag>..HEAD -- <component paths>`.
- A commit releases a component when its type is `feat`, `fix`, `perf` or breaking (`!` or a
  `BREAKING CHANGE` footer) and it changes a file under a path of the component.
- `chore`, `ci`, `docs`, `test`, `style`, `refactor` and `build` commits never release.
- A non-conventional commit after the latest tag keeps `check` red until a tag follows it.

## Read the release dry run

| Output | Meaning | Next step |
|---|---|---|
| a version, a tag, files and notes per component | a release is proposed | tell the developer the list, ask for the go |
| `Nothing to release` | no releasing commit after the latest stable tag | find a real change; never fake one |
| a component marked pending, tag is HEAD | the tag exists on `HEAD`; the apply pushes it and creates the GitHub Release | tell the developer; the tag is a baseline, not a new version |
| exit 1 | the working tree is dirty, or the minimum check is red | fix the cause first |
| exit 3 | `user.name` or `user.email` is unset, or a version file is refused | read the message |

## Apply a release

- Preconditions: on the main branch, clean working tree, Docker and the token service running.
- Effect: the release commit `chore(<component>): release <tag>` on the main branch, the tag and the
  GitHub Release, all as the App; the version files and the changelog are written by the commit.
- Pre-release: `--pre <channel>` with a lower case channel such as `rc`; `--draft` leaves the GitHub
  Release unpublished.
- A wrong release is corrected by a new release.

## Before a promote

- Promote accepts a tag whose commit is `chore(<component>): release <tag>`; a baseline tag or
  a hand made tag is refused.
- When both branch settings are `master`, there is nothing to promote.
- Dry run first: it prints the commit, the release branch position and, when the release branch is
  not an ancestor of the release commit, the divergence.
- Fast forward: `promote <tag> --apply`.
- Baseline mode: `promote <tag> --apply --confirm <owner/repo>`. The old head of the release
  branch is kept as the tag `legacy/pre-promote`, and the branch is moved with a lease.
- Baseline mode happens once per repository, after the first real release of a migrated repository.

## No backport

- A release is made on the main branch only, and promote moves the release branch to a release tag.
- A fix reaches the release branch through a pull request, a release and a promote.
- Every unreleased `feat`, `fix` and `perf` commit on the main branch ships with that release.
- Show the developer the dry run when the main branch holds features that must not reach production;
  the choice is to ship them with the fix or to wait.

## Split

- Applies to components with `split: yes` in `components.yaml`; it needs two or more versioned
  components.
- Dry run: `split [component]` prints the split head, the ancestry to the child head and the tree
  difference; the apply takes exactly one component.
- Apply: `split <component> --apply`, with the App installed on the child repository.
- Replace a child that does not descend from the split: `--confirm <owner/child>`; the old head is
  kept as the tag `legacy/pre-split`.
- A child tag at another commit is skipped with a warning and never moved.
- A child whose default branch differs from the main branch is refused.
- Only the first path of a component is split.

## Rulesets and shims

- `rules-sync` is a dry run by default; `--apply` creates or updates the rulesets as the App
  and takes `--stage development|production`.
- `shims` installs the commit-msg and pre-push shims; `shims --check` reports and changes nothing.
