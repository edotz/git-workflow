# edotz.git-workflow: a possible process for a single repository and a monorepo

Companion of `261102-git-workflow-whitepaper.md`. It describes how a developer works with the plugin, step by step,
if the positions of the white paper are taken. Nothing here is implemented. Provenance tags as in the paper:
**[Dn]** concept decision, **[input]** owner decision of this discussion, **[proposed]** this document's suggestion,
**[open]** unresolved, **[verify]** unchecked fact. Q-ids refer to the register of the paper.

---

## 1. Building blocks shared by both processes

### 1.1 Roles and credentials

| Actor | Does | Credential |
|---|---|---|
| Developer | works on a branch, runs `app git …`, opens PRs | own `gh` login; no write right on a released branch |
| GitHub App | pushes the release commit and tag, creates the GitHub Release, pushes the split, syncs rulesets | short-lived installation token from the token service [D6], never a stored key |
| GitHub | runs the status checks, squash-merges PRs, enforces the rulesets | built-in |
| Consuming project | deploys, publishes, applies Terraform, in its own workflows | its own, never the plugin's [input] |

### 1.2 One-time setup per repository

1. Install the GitHub App on the repository.
2. Write the configuration: `workflow.env` (`MAIN_BRANCH`, optional `RELEASE_BRANCH`, `STAGE`), and for a monorepo the
   component declaration (Q-O).
3. `app git workflow-setup` validates the configuration and generates `status-checks.yml`, the only workflow.
4. `app git rules-sync --dry-run`, then `--apply`: one ruleset for the released branches (PR required, linear history,
   the aggregate check required, the App as sole bypass actor), and the repository settings for squash-only merging
   with the PR title as the commit title **[verify]**.
5. Hooks: the `commit-msg` hook validates the message with `git lint-commit`.
6. The tool image (git-cliff, splitsh-lite, gh) is built on first use by the shim (11.1 of the paper).

### 1.3 The daily loop

Identical for a single repository and a monorepo.

| # | Step | Command | What it checks or does |
|---|---|---|---|
| 1 | Branch | `app git start` or `app git worktree` | branch from `MAIN_BRANCH`, type and name checked |
| 2 | Work and commit | `app git commit` | message from the staged diff by the provider, optional; always passes `lint-commit` |
| 3 | Open the PR | `app git pr` | push, PR with a conventional title (the future commit), auto-merge with squash enabled |
| 4 | Gate | GitHub | the aggregate check; no human merge step |
| 5 | Merge | GitHub | squash onto master, branch deleted; master gets one commit per PR |

The PR title is what the changelog shows, so it is linted like a commit message. After step 5 the developer does
nothing more; there is no promotion, no backport and no release PR.

### 1.4 The release loop

```
app git release [<component>] --dry-run
  guards     clean tree, HEAD equals origin/<branch>, checks green on HEAD
  version    last tag + commits touching the component's paths (git-cliff), or --version <x.y.z>
  preview    release notes (written to a file the developer can edit), the files that change

app git release [<component>] --apply [--notes-file <file>] [--draft]
  commit     chore(<component>): release vX.Y.Z   (version files, CHANGELOG, README if declared)
  tag        <component>/vX.Y.Z, or vX.Y.Z in a repository with one component
  push       branch and tag in one atomic push, as the App
  release    the GitHub Release for the tag, with the notes
```

- The commit is made locally with the developer as author; only the push and the Release are made as the App.
- A repeated `--apply` after a failure creates only what is missing.
- `--draft` leaves the Release unpublished, so a person publishes it on GitHub **[proposed]** (8.1 of the paper, Q-L).
- What happens after the Release belongs to the project: deploy, publish, `terraform apply` (8.3).

### 1.5 Guards

| Guard | Stops | Where |
|---|---|---|
| `lint-commit` | a non-conventional message | `commit-msg` hook, and the PR title check |
| aggregate check | a PR whose affected checks fail | GitHub, required by the ruleset |
| ruleset | a human push to a released branch | GitHub |
| release guards | a dirty tree, a stale `HEAD`, red checks on `HEAD` | `release --dry-run` and `--apply` |
| atomic push | a release on a master that moved | git; the non-fast-forward push is rejected |
| read-back | a version file that was not written | `release --apply`, per file (6.3) |

### 1.6 Failure and repair

| What goes wrong | What happens | Repair |
|---|---|---|
| a check fails on the PR | the PR does not merge | push a fix to the branch |
| master moves between dry run and apply | the push is rejected, nothing is public | run the command again |
| the notes or the version are wrong | caught by the dry run | edit the notes file, or pass `--version` |
| the Release call fails after the push | a tag without a Release | run `--apply` again |
| a version file cannot be written | `--apply` stops before the commit | fix the config or the writer |
| the token service is down | no App token, no release and no split | wait; nothing else is affected |
| the commit message is rejected | the commit is not created | edit the message |

---

## 2. Single repository

### 2.1 Shape

A single repository is a monorepo with one component at the root [paper 6.6]. Its tags are `vX.Y.Z`. `master` is the
development and release branch, and there is no promotion.

### 2.2 Setup

`workflow.env` with `MAIN_BRANCH=master`, the version files (`package.json`, `composer.json`, `ext_emconf.php` or
similar), and the optional publish consumer. Steps 1.2 follow.

### 2.3 A release, with commits

Starting state: the last tag is `v1.2.0`, and master carries three squash commits since.

```
fix(parser): handle empty input
feat(export): add csv export
docs: describe the export option
```

1. `app git release --dry-run` computes `1.3.0` (the `feat` bumps the minor version), writes the notes (a Features
   and a Fixes group, with `docs` in the changelog and no bump of its own), and lists `package.json` and `CHANGELOG.md`.
2. The developer edits one line of the notes.
3. `app git release --apply --notes-file …` commits `chore(root): release v1.3.0`, tags `v1.3.0`, pushes both as the
   App, and creates the GitHub Release `v1.3.0`.
4. The project's own workflow on `release: published` publishes the package, if there is one.

The name of the root component in the commit scope is open **[open]**.

### 2.4 A fix for an old line

1. `git switch -c 1.x v1.2.0` and push the branch once; the ruleset treats it like master.
2. The fix goes in by a normal PR to `1.x`, or by cherry-pick from master.
3. `app git release --dry-run` on `1.x` computes `1.2.1` from the tag `v1.2.0`; `--apply` releases it.

`RELEASE_BRANCH` names such a line only when a project keeps one permanently (6.4 of the paper, Q-N).

---

## 3. Monorepo

### 3.1 Shape

The repository holds components (frontend, CMS, infrastructure, packages), each with its own version and release,
declared in one place (6.6 of the paper). The daily loop of 1.3 is unchanged. Differences:

| Concern | Monorepo |
|---|---|
| Declaration | `name`, `paths` or `workspace`, `version_files`, `version`, `split`, `checks` (Q-O, Q-R) |
| Checks | one always-running workflow detects the changed components and runs their checks; the aggregate check is the only required one |
| Tags | `<component>/vX.Y.Z` |
| Release unit | one component, or `--all` |
| Split | per component, only with `split: yes` |

### 3.2 Checks follow the change

1. A PR is opened. `status-checks.yml` runs, starting with change detection.
2. For a JavaScript workspace, `turbo run <tasks> --affected` decides which tasks run (Q-R). Other components are
   matched by their paths.
3. The commands the project declares run (Q-P): for example `turbo run lint check-types build`, `composer` checks,
   `terraform fmt -check` and `validate`.
4. The commit lint of the PR title runs.
5. The aggregate job reports the single required check.

Adding a component never changes the ruleset.

### 3.3 A walkthrough in hh-web

The components are `web`, `typo3` and, after the move, `infra` (Appendix B of the paper).

| Step | What happens |
|---|---|
| `fix(ui): button focus ring` | the PR touches `packages/ui`; turbo marks `hh-website` as affected; its tasks run; the aggregate passes; squash merge |
| `feat(infra): route /api through nginx` | the PR touches `infra/`; the Terraform checks run; merge; the apply is done by hand |
| `app git release web --dry-run` | version from `web/v0.1.0` and the commits touching `apps/web`, `packages/ui`, `packages/api-client`; notes; `apps/web/package.json` listed |
| `app git release web --apply` | `chore(web): release v0.1.1`, tag `web/v0.1.1`, push, GitHub Release |
| the project's deploy workflow | fires on `release: published`, filtered on `web/`, builds and deploys the frontend |
| `typo3` and `infra` | untouched; no tag, no Release |

### 3.4 Releasing several components

`app git release --all --dry-run` lists every component with pending changes and its next version. `--apply` releases
them one after the other in declared order, as separate commits with separate tags and Releases. A failure stops the
run; a repeat continues with what is missing. There is no lockstep mode.

### 3.5 Splitting a component

Only for a component with `split: yes`, for example a PHP package for Packagist.

1. `app git release <component> --apply` releases it in the monorepo as above.
2. `app git split <component> --dry-run` runs `splitsh-lite --prefix=<path>`, prints the split SHA and the target
   repository derived from the declaration, and checks that the monorepo `HEAD` equals `origin/<branch>`.
3. `app git split <component> --apply` pushes the SHA to the child repository over HTTPS as the App, pushes only this
   component's tag with its prefix removed, and creates the child's GitHub Release.
4. The first split of an existing child is a baseline that needs a force push and a confirmed dry run (7.3 of the paper,
   Q-C).

An integrated product such as hh-web has no split component, so none of this applies there.

### 3.6 A new component

1. Add the component to the declaration.
2. Run `app git workflow-setup`; the ruleset does not change.
3. Its first PR runs its checks. Its first release starts from `0.1.0` with no earlier tag **[open]**.

---

## 4. What the developer no longer does

- no promotion PR and no release branch to keep in sync
- no backport PR and no README commit afterwards
- no release PR from a bot, and no manual tag
- no personal token and no private key on the machine
- no cloud workflow to wait for between a release and its result

---

## 5. Open points of the process

| Point | Where |
|---|---|
| Commit scope of a root component, first tag of a new component | 2.3, 3.6 |
| Whether a release is created as a draft by default | Q-L |
| What the development phase of STAGE relaxes, for example in a proof of concept | D21 |
| Pre-releases: tag only, or a commit as well | Q-H |
| Whether a release touches a README | D22, Appendix B of the paper |
| Format of the component declaration | Q-O |
