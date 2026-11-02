# edotz.git-workflow: a local, deterministic Git workflow for agentic-os

White paper, discussion basis for the concept `git-workflow-plugin`. Status 2026-11-02. Positions tagged [input] are
the owner's decisions of this discussion and are not yet recorded in the concept; everything else is a basis for
discussion.

Provenance tags used throughout:

- **[Dn]** a decision already recorded in `CONCEPT-git-workflow-plugin` (D1 to D26)
- **[input]** a statement of the owner made after the concept was written, not yet recorded in it
- **[proposed]** a position of this paper or of the concept that nobody has confirmed
- **[open]** a question without an answer
- **[verify]** a factual claim that was not checked against current documentation

Sources: `260903_edotz_gitworkflow.pdf` (analysis), `260903-git-workflow.md` (draft design), the concept, the old
reference docs in `docs/git-workflow*`, the six workflows in `.github/workflows`, and `edotz.monorepo-split-action`
(read: `action.yml`, `Dockerfile`, `entrypoint.php`, `MonorepoSplitter.php`, README).

A possible process for a single repository and for a monorepo, built on this paper, is in
`261102-git-workflow-process.md`.

---

## 1. Summary

The old workflow gets a change from a feature branch to a published release through up to five chained pull requests
and workflows, all of which authenticate with one developer's personal access token. It cannot be previewed or repaired
locally, it produces backport conflicts, and it is currently kept from firing at all by holding the versions back.

The plugin replaces the cascade with a local workflow behind one entry point, `app git <command>`. GitHub only gates
pull requests. A release happens on the development branch: one commit that aligns the version in the manifest files,
with its tag, made locally and pushed by a GitHub App that is the only bypass actor; there is no standing release branch
and no promotion (section 6) [input]. The release is also provided as a GitHub Release; how it gets created is open
(section 8.1). The monorepo split runs from the developer machine, and the container carries only the tools (11.1).

The monorepo is treated as an integrated product of components such as frontend, API, CI and infrastructure, with
splitting only for components that need their own repository (6.6, 7). The plugin ends at the release; publishing,
deployment and provisioning belong to the consuming project (8.3) [input].

The central design is decided. What remains open:

1. How GitHub's single "latest release" per repository works with several components, and how the READMEs link to a
   component's release (Q-Q).
2. How the existing child repositories move from the action's merge-commit history to a split history, for the
   components that are split (section 7).
3. Pre-release handling (Q-H), and how a project's own checks join the aggregate check (Q-P).

---

## 2. Starting point

### 2.1 Two topologies

| | Single repo | Monorepo split |
|---|---|---|
| Versioned unit | the repo | each child repo; the monorepo is never versioned |
| Release trigger | promote PR merges into `RELEASE_BRANCH` | promote PR merges, split action pushes, child pipeline fires |
| Release tool | release-please on `RELEASE_BRANCH` | release-please in every child repo |
| README | `post-release` workflow, then backport PR to `MAIN_BRANCH` | `sync-to-monorepo` workflow, then backport PR to the monorepo |
| Merge policy | merge commits only, squash and rebase disabled | same; the backport PR is the single squash exception |

### 2.2 The chain

```
single repo
feature PR -> master (auto-merge)
  promote PR master -> 2.x (Stage Guard)
    release-please -> release PR -> auto-merge -> tag
      post-release -> README -> backport PR -> master

monorepo
feature PR -> master
  promote PR -> 1.x -> split action (matrix, personal token) -> child repo
    child release-please -> release PR -> auto-merge -> tag
      release-publish (node)
      sync-to-monorepo -> backport PR -> monorepo
```

### 2.3 What exists today

- Five callable workflows plus `status-checks.yml`, all generated per repo from `.github/workflow.env` by
  `workflow-setup` (callers, `branch-protection.yaml`, `release-please-config.json`).
- Nine pinned third-party actions that every consuming repo must keep aligned.
- Four callables use `NPM_AUTH_TOKEN`, the personal token of `ohoeft`.
- Classic branch protection, where `enforce_admins` is toggled by `STAGE` and `ohoeft` is the bypass.
- A pre-flight gate (`/git:setup-workflow`) that exists to catch drift between generated files and templates, and to
  catch release-please manifest mismatches.
- The versions are deliberately held back at the moment, so the release-please pipeline does not run.

---

## 3. Problem analysis

| # | Failure class | Mechanism |
|---|---|---|
| F1 | Cascade fragility | Every hop is an asynchronous event. One failed manifest validation or API throttle stops the train mid-way, and the state is half published. |
| F2 | No local repair | Changelog and version are computed in the cloud by release-please. Bad changelog entries are fixed with empty commits carrying `Release-As:` or by editing closed PR bodies. |
| F3 | Backport conflicts | README, manifest and changelog return to `MAIN_BRANCH` through an asynchronous PR. Development continues meanwhile, so the PR conflicts on exactly those files. |
| F4 | Personal credential | Every write path (runner auth, split push, PR creation, protection bypass) runs as one person. Absence or token expiry stops everything. |
| F5 | Split semantics hidden in CI | The split action resolves merge conflicts with `--theirs` and creates reconcile commits, in a cloud job nobody watches. |
| F6 | Generated-file maintenance | Per-repo generated callers, a template drift gate and pinned versions across repos are a maintenance load of their own. |
| F7 | Child repos run their own release | Each child has a second pipeline, a second token consumer and a second backport path. |

The PDF names F1 to F4. F5 to F7 come from reading the code and the old docs. They matter because removing the
release-please chain removes F1 to F3, but F5 to F7 only disappear if the split and the generation are redesigned as
well.

---

## 4. Principles

Derived from the concept's decisions [D4, D7 to D9, D14, D15].

- **P1 Local first, GitHub only gates.** Everything that computes (version, changelog, README, split) runs locally and
  can be previewed. GitHub runs the PR checks and holds the rules.
- **P2 Deterministic and idempotent.** The same input gives the same result, and a repeated command is a no-op. This is
  the property that makes a local release safe to retry.
- **P3 No personal credential.** Every GitHub write right belongs to the App. No private key reaches a developer
  machine [D4, D5, D6].
- **P4 One entry point.** `app git <command>`, subject to the same module rules as every framework command [D3].
- **P5 The developer does not care how a change is incorporated** [D8]. Merge method, linearity and changelog entry
  are the tool's business.
- **P6 Fewer generated artifacts.** One workflow file instead of a generated set per repo [D19].
- **P8 The plugin ends at the release.** What happens after a release belongs to the consuming project [input].
- **P7 Fewest moving parts.** No standing release branch, no promotion, no asynchronous step between a local release
  and its result [input]. A feature is accepted only if it does not need one of those.

---

## 5. Target model

### 5.1 Decided

| Topic | Position |
|---|---|
| Command surface | `app git <command>`; the names `gh wf`, `gh-wf`, `git-wf` are dropped [D3] |
| Identity | GitHub App replaces the personal token completely [D4] |
| Bypass | The App is the only bypass actor on every released branch, master included; humans cannot push there [D5 revised, input] |
| App token | A token service issues short-lived installation tokens to the CLI [D6]; its design is left to the plan [D23] |
| Merge policy | Squash merge on master; master, release and legacy branches are all linear; the changelog entry is the PR title [D11] |
| Release | `release --dry-run` previews version and changelog with git-cliff; `release --apply` writes the version files, CHANGELOG and README into one release commit with its tag and pushes both as the App [D15, section 6] |
| Release branch | None standing and no promotion; the development branch is released. `RELEASE_BRANCH` is optional and names a maintenance line [D12 and Q12 dissolved, D16 revised, input] |
| Version files | `version_files` of a component lists them; one writer per file kind, read back after writing (6.3) [input] |
| LLM steps | Commit message and changelog summary through `provider_run_prompt` on the host session; the plugin neither chooses nor bundles a provider [D10, D18] |
| Container | Carries only the deterministic tools git-cliff, splitsh-lite and gh [D18]; host `app` calls them through a shim, `app` is not its entrypoint [input, revises the D3 wording] |
| STAGE | Stays as a project-phase switch for the master ruleset; the Stage Guard goes [D17] |
| Old CI | Everything except `status-checks.yml` is removed [D19] |
| Split | Runs locally with splitsh-lite and pushes the child repositories [concept measures]; per component, only where `split: yes` (7) [input] |
| Components | A monorepo is an integrated product of components (frontend, API, CI, infra, packages) declared in one place; the components are not deployed together, so each is versioned and released on its own, with tags `<component>/vX.Y.Z` (6.6) [input] |
| Boundary | The plugin ends at the release. Publishing, deployment and provisioning belong to the consuming project (8.3) [input] |
| GitHub Releases | Releases are still provided over GitHub; the tag alone is not enough. The way is open (Q-L) [input]. The concept so far names the tag and the release commit but no Release object. |

### 5.2 Target flow

```
app git start      branch from MAIN_BRANCH
app git commit     message from the staged diff, validated by lint-commit
app git pr         push, open PR with a conventional title
                   GitHub: status checks gate; squash merge to master
app git release    --dry-run: version, notes and the files that change
                   --apply:   one release commit + tag on the released branch, pushed as the App
                   GitHub Release for that tag: mechanism open                  (section 8.1)
package release   separate stage after the git release, node packages only: publish (section 8.2)
app git split      monorepo only: splitsh-lite per package, push to child repos
```

Five local commands, plus `rules-sync`, replace twelve chained steps and five workflows. The step-by-step processes for a
single repository and for a monorepo are in `261102-git-workflow-process.md`.

### 5.3 The old and the new model side by side

| Concern | Old | New |
|---|---|---|
| Version and changelog | release-please, cloud | git-cliff, local |
| README | `post-release`, then backport PR | written into the release commit |
| Tag | release PR merge | local, in the release commit |
| GitHub Release | created by release-please | still provided; mechanism open (8.1) |
| Split | cloud matrix job, personal token | local splitsh-lite, App token |
| Child release | release-please per child | none; tags come from the monorepo release |
| Protection | classic branch protection, `ohoeft` bypass | rulesets, App bypass |
| CI | six workflows, nine pinned actions | `status-checks.yml` only |

---

## 6. Releasing on the development branch [input]

The release model is decided by the owner and replaces the promotion model of the concept. Reasons: the version has to
be aligned in `package.json`, `composer.json`, `ext_emconf.php` and similar files, so a release commit is required,
and the owner wants the fewest moving parts.

### 6.1 The decision

- The release happens on the branch that is developed, `master` by default. There is no standing release branch and
  no promotion. `RELEASE_BRANCH` becomes optional and names a maintenance line (6.4).
- The release commit is pushed directly, together with its tag, by the GitHub App as the sole bypass actor of the
  ruleset of the released branch. Humans cannot push there. The App token comes from the token service [D6].
- Consequently the concept changes as follows:

| Decision | Effect |
|---|---|
| D5 | revised: the App is the sole bypass actor on every released branch, master included |
| D12, Q12 | dissolve: nothing is promoted, so nothing is replayed |
| D15 | kept: one release commit with its tag, made locally |
| D16 | `RELEASE_BRANCH` optional, default `MAIN_BRANCH` |
| D9 | master now tracks the version |

### 6.2 How a release runs

```
release --dry-run
  preconditions   clean tree, HEAD equals origin/<branch>, status checks green on HEAD
  version         next version of the component: last tag plus the commits touching its path (git-cliff),
                  or --version <x.y.z>
  preview         release notes, the version files that change, the files the commit touches
release --apply
  commit          one commit `chore(<component>): release vX.Y.Z` with the component's version files,
                  CHANGELOG and README
  tag             <component>/vX.Y.Z on that commit (vX.Y.Z when the repo has one component)
  push            branch and tag in one atomic push as the App
  release         the GitHub Release for the tag (8.1)
```

- Fixing a release before it is public means editing the notes file or passing `--version`. The empty-commit hacks with
  `Release-As:` are gone [F2].
- If master moves between the dry run and the push, the push is rejected because it is no longer a fast-forward.
  Re-run the command. No release is half published, since commit and tag go in one push.
- Re-running after a failure after the push only creates what is missing, normally the GitHub Release.
- git-cliff has to skip release commits in the changelog.

### 6.3 Aligning the version in files

- The `version_files` field of a component (6.6) lists the files.
- One small writer per file kind: JSON for `package.json` and `composer.json`, a pattern writer for `ext_emconf.php`.
  The command reads each file back after writing it and fails when the version is not the one it wrote. A file kind
  without a writer is a configuration error, not a silent skip.
- `--dry-run` lists every file that would change.
- Composer itself discourages a `version` field, because it reads the tag **[verify]**, so for PHP the file may be
  optional per project. `ext_emconf.php` needs it, and its writer has to be checked against the real file layout
  **[verify]**.

### 6.4 Maintenance lines

- An old line such as `1.x` is a branch cut from a tag when a fix needs it, or from a chosen SHA when only part of
  master should ship. It is an ordinary protected branch with the same ruleset: PRs, linear history, the App as bypass.
- Fixes reach it by a normal PR or by cherry-pick. `release` runs on it exactly as on master.
- `RELEASE_BRANCH` names such a line when a project keeps one permanently. With none configured, `master` is released.

### 6.5 What this removes and what it costs

Removed: the `promote` command, replay and its `-x` bookkeeping, Q12, the question where the changelog lives (it is on
the released branch, so on master), the single-branch special case, and the standing release branch with its ruleset.

Costs, to be accepted knowingly:

- The release commit reaches master without CI. The dry run and the local `lint-commit` are its only check.
- A release always contains everything on master. A subset needs a maintenance branch from that SHA.
- The App can push anything to a released branch. Its token is issued only to team members through the token service,
  and the same trust already held for the release branches in D5.
- One release commit per release of a component is in the history of master. Pre-releases make one too, because the version
  files carry the pre-release version; whether pre-releases are tag-only is open with Q-H.
- The ruleset's bypass mode has to allow the App's direct push **[verify]**.

### 6.6 Components of an integrated monorepo [input]

The monorepo is mostly an integrated product: frontend, API, CI and cloud provisioning in one repository, with some
parts changing far more often than others, especially at the start. The release model above applies to the whole
repository.

**Scope boundary [input].** Provisioning (for example Terraform) belongs to the consuming project. The plugin ends at
the release: tag, GitHub Release, notes and version files. Anything that happens after it is a consumer of the
Release (8.3).

**Component declaration.** One declaration at the repository root lists the components. It replaces `PACKAGES_DIR` and a
`workflow.env` per package. Fields:

| Field | Meaning |
|---|---|
| `name` | the component name, also the allowed commit scope |
| `paths` | its directories, including shared code it depends on; a change in any of them is a change of the component, for the bump and for the checks; a move is a one-line edit |
| `kind` | frontend, api, ci, infra, package; selects the default checks |
| `version` | `yes` (default) or `none`; a versioned component is released on its own |
| `version_files` | the files the release commit aligns (6.3) |
| `split` | `yes` only if the component needs its own repository (7) |

**Versioning [input].** The components are not deployed together, so each versioned component has its own version and
is released on its own. There is no lockstep mode, which keeps one mechanism.

- **Unit.** `app git release <component>`. `release --all` releases every component with pending changes, one commit
  and one tag each, in declared order. A single repository is the same model with one component at the root.
- **Next version.** From the component's last tag and the commits that touch its path since then (git-cliff with a path
  filter and a tag pattern). The bump derives from paths and not from the commit scope, because a scope can be wrong. A
  commit that touches two components counts for both.
- **Tag.** `<component>/vX.Y.Z`; a repository with one component keeps `vX.Y.Z`.
- **Release commit.** `chore(<component>): release vX.Y.Z`, touching only that component's version files, CHANGELOG and
  README, which live in its directory.
- **GitHub Release.** One per component tag, with the notes of that component.
- **`ci` and `infra`.** They default to `version: none`. A project that wants a tag to apply Terraform from sets
  `version: yes`.
- **Costs.** A directory move counts as a change once and causes one extra bump. A repository carries several tags and
  Releases, and GitHub has one "latest release" per repository (Q-Q). Compatibility between components, for example a
  frontend that needs an API version, is the project's concern.

**Commit scopes are free.** The release logic reads paths, not scopes, so a scope has no function beyond readability.
The commitlint rule stays as it is in practice: a lower-case scope, no list of allowed scopes. A scope list would
reject the scopes real projects already use (Appendix B).

**Workspace projects.** In a pnpm and Turborepo project the workspace graph already says which package depends on which,
and `turbo --affected` says what changed. A component of such a project names its workspace package instead of
repeating paths, takes its paths from the dependency graph, and runs its checks as `turbo run <tasks> --affected`. The
declaration does not restate what pnpm and turbo know. Other components, such as TYPO3 and Terraform, are declared by
paths [proposed, Q-R].

**Checks follow the change.** One `status-checks.yml` always runs. A first job detects the changed components, the
checks of their kinds run as conditional jobs, and a final aggregate job is the only check the ruleset requires. Path
filters on a required workflow can leave the check pending and block the PR, so the filtering happens inside the
workflow **[verify]**. Adding a component never changes the ruleset. How a project's own checks, for example
`terraform fmt` and `validate`, join the aggregate is open (Q-P).

**Graduation by configuration.** A new project starts with all components at `0.x`, no splits and the lighter STAGE
phase (D17). When a component gets consumers, its `split` flag or its checks change. Nothing is restructured.

---

## 7. The monorepo split

Splitting is per component (`split: yes`, 6.6) and only for components that need their own repository, for example a
PHP package for Packagist, which reads `composer.json` at the repository root. An integrated product has none, and
then this section does not apply to it.

### 7.1 What the current action does

The action is a PHP Docker action, and it does not use splitsh-lite:

1. clone the child repo with the token over HTTPS
2. compare package content (`git archive` plus `rsync`), exit early if equal
3. `git subtree split --prefix`
4. drop commits that do not touch the package (cherry-pick into a filtered branch)
5. reconcile the working tree with a `chore(monorepo): reconcile…` commit
6. `git merge --no-ff --allow-unrelated-histories`, resolving conflicts with `--theirs`
7. push

The child history is therefore a merge-commit history on top of whatever the child already contained.

### 7.2 What the concept replaces it with

`splitsh-lite --prefix=packages/<name>` returns the SHA of a deterministic split history, and the CLI pushes that SHA to
the child [concept measures]. The same monorepo state always yields the same SHAs, so a repeated split is a no-op. This
replaces the content comparison, the reconcile commit and the cross-package filter, and removes `--theirs`
auto-resolution (F5).

### 7.3 What the move costs

- **History divergence.** Existing children carry merge commits, reconcile commits and an "Initial commit". The
  splitsh-lite history shares no SHAs with them, so the first push cannot be a fast-forward. Each child needs a
  one-time baseline, which means a force push of its release branch. That is the only destructive step in the whole
  design and needs a confirmed dry run per child.
- **Tags.** The draft's `git push … --tags` sends every monorepo tag. A child gets only its own, and a tag such as
  `packages/object/v2.1.0` has to be mapped to the child's tag name. splitsh-lite itself does not carry tags.
- **Child release pipelines.** They must stop. The versions are already held back, so the practical step is to delete
  the generated child workflows and `release-please-config.json` per child, and to let the monorepo release push tags.
- **Child protection.** The children currently let `ohoeft` push directly. The App has to be installed on every child
  with contents write, and be the bypass actor there.

### 7.4 Where the child URLs come from

The concept does not say. The data exists: `REPO_OWNER` and `REPO_NAME` in `packages/<name>/.github/workflow.env`,
`MONOREPO_PACKAGE` as the path, `PACKAGES_DIR` at monorepo level. Proposed:

- The URL is derived from the manifest as `https://<host>/<REPO_OWNER>/<REPO_NAME>.git`, host defaulting to
  `github.com`, with an optional `REPO_URL` override per package.
- A component participates only if it is declared `split: yes`, which replaces the per-package manifest as the opt-in
  signal; owner and repo name become fields of the component declaration.
- The push goes over HTTPS with the installation token. SSH would bring back a personal key.
- The CLI refuses to split from a dirty tree or from a `HEAD` that differs from `origin/<branch>`.

**[open]** Does a package get its own version, or does the monorepo release carry one version for all? D24 leaves this
to the plan, but it decides the tag mapping and whether `release` runs per package.

### 7.5 Fate of `edotz.monorepo-split-action`

It becomes unused and can be archived. Its useful semantics map over: the manifest opt-in stays, content-based
idempotency is replaced by determinism, and the cross-package filter is replaced by path-based splitting.

---

## 8. Release engineering

- **Version.** git-cliff derives the next version from conventional commits: `feat` minor, `fix`, `perf`, `revert`
  patch, `!` or `BREAKING CHANGE` major, `chore`, `ci`, `build` none, `docs` changelog only (the existing table).
- **Pre-releases.** The PDF credits git-cliff with `--pre=<channel>`. **[verify]** whether git-cliff increments a
  pre-release counter or whether the CLI has to implement it. The tag format for monorepo packages is open (D24).
- **One source of commit types.** commitlint config and `cliff.toml` must derive from the same list, or a type that
  lints clean is silently dropped from the changelog.
- **README.** `generate-readme-action` runs only as an action today. The release commit needs a local generator [D22,
  left to the plan]. Its inputs are known: `docs/readme-config.json`, `docs/README.md`, a type template and the version.
- **Manifests.** `package.json` and `composer.json` are rewritten by the CLI. `.release-please-manifest.json` goes.
- **Dry run.** `--dry-run` writes nothing and prints version, changelog and the list of files `--apply` would change.

### 8.1 Providing releases over GitHub [input]

The owner wants releases to stay available on GitHub. The way is open. release-please creates the GitHub Release today
together with the tag, so removing it would drop the Release object unless something else creates it. The old README
depends on it: the `releases/latest` links and the version badges read the newest GitHub Release.

**What any option has to satisfy**

- One Release per release tag, in the repo consumers use: the child repo for a monorepo package, the repo itself for a
  single repo.
- Notes from the git-cliff output of that release, optionally with the LLM summary on top.
- A pre-release flag maps to GitHub's pre-release marker; "latest release" ignores pre-releases and drafts, so
  `releases/latest` keeps pointing at the last stable version **[verify]**. With several components in one repository
  this gets ambiguous, because GitHub has one "latest release" per repository (Q-Q).
- No personal credential [P3], no new asynchronous hop that can strand a release half published [F1], and a missing
  Release can be repaired by re-running the command [P2].

**Options**

| | A CLI creates it | B CLI drafts, a person publishes | C Workflow on tag push | D Release PR on GitHub |
|---|---|---|---|---|
| Mechanism | `gh release create` as the App at the end of `release --apply` | same call with `--draft`; publish in the GitHub UI or with a later command | `on: push: tags` workflow creates the Release with the built-in token | the release is prepared as a PR and merged on GitHub, then tagged and released |
| Asynchronous hop | none | none until published | one | one or more |
| New file in each repo | none | none | yes, one workflow per repo and child | none |
| Fits D19 (only `status-checks.yml`) | yes | yes | no, needs an amendment | yes |
| Credential | App token | App token, publish by the person | built-in `GITHUB_TOKEN` | App token |
| Review on GitHub before it is public | no | yes | no | yes, on the PR |
| Repair | re-run, creates the missing Release | re-run, or edit the draft | re-run the workflow | follows the PR |
| Status | | | | dropped: the release commit is pushed directly (section 6), no release PR exists |

A and B are one mechanism with a switch, so they can be offered together: `release --apply` creates the Release, and
`--draft` leaves it unpublished. C is the only option that gives up part of the local-first principle and adds a
generated file per repo, which is the maintenance load of F6 and F7 again. D carries the Release only if the topology
itself becomes a release PR.

**Leaning.** A, with B as the `--draft` variant. This is a lean, not a decision.

**What stays the same in every option**

- Failure between the tag push and the Release leaves a tag without a Release. The command is idempotent: it detects
  the pushed tag and creates only what is missing.
- For a monorepo the Release goes to the child repo. With the split SHA already pushed, `gh release create <tag>
  --target <sha> -R <child>` should be able to create the tag on the child commit in the same call **[verify]**. Whether
  the monorepo itself also gets a Release is part of Q-D.
- Publishing an artifact to a registry is not part of the git release. It is a separate stage, see 8.2.

### 8.2 Two stages: the git release and the package release [input]

The old design mixes two things under "release". The paper separates them.

| | Git release | Package release |
|---|---|---|
| Output | release commit, tag, GitHub Release object | an artifact in a registry (npm, GitHub Packages) |
| Owner | the plugin, locally (`release --apply`) | the consuming project, starting from the Release (8.3) |
| Needed by | every project | only projects that publish an artifact |
| Credential | the App token | the registry credential |
| Failure | repaired by re-running `release --apply` | repaired by re-running the publish, the git release stays untouched |

- The version number belongs to the git release: the version files (6.3) are rewritten inside the release commit.
  Publishing only uploads what the tag already contains.
- Some types need no publish stage at all. PHP packages are read from the tag by Packagist, and `simple` and `bash`
  projects have no artifact **[verify]** the Packagist update path.
- `RELEASE_TYPE` drives both today (release-please type, backport files, publish). It splits into the type that tells
  `release --apply` which manifests to write, and an optional publish target per project or package.

**Where the package release runs.** The registry credential decides.

- GitHub Packages for npm accepts the built-in `GITHUB_TOKEN` inside a workflow. An App installation token very likely
  cannot publish to it **[verify]**, and a personal token is excluded [P3]. This points to one small workflow on
  `release: published`, using `GITHUB_TOKEN` with `packages: write`.
- A Release created with an App token starts that workflow, one created with the built-in token does not
  **[verify]**. So the git release by the CLI as the App (options A and B in 8.1) is the combination that fires it.
  Option B gives a manual gate: the publish starts when a person publishes the draft.
- That workflow is owned by the consuming project, like deployment and provisioning (8.3). The plugin ships none, so
  D19 stays intact.

**[settled, Q-J] [input]** The package release is project-owned and starts from the Release. The plugin may document an
example workflow for node packages, and nothing more.

### 8.3 The boundary: after the release [input]

The plugin ends at the release. What follows is a consumer of the GitHub Release, owned by the consuming project:

| Consumer | Example | Trigger |
|---|---|---|
| Package publish | npm, GitHub Packages | `release: published` |
| Deployment | frontend, API | `release: published` or a tag |
| Provisioning | Terraform apply per environment | `release: published`, or run by the project's own tooling |

The plugin guarantees only the contract: a tag `vX.Y.Z` on a commit with aligned version files, a GitHub Release for
it with notes, and, for a split component, the same in the child repo. It holds no cloud credential and no deployment
logic. A Release created with an App token starts workflows, one created with the built-in token does not
**[verify]**, so the contract states that the Release is created as the App. A `release: published` event fires for every component
of the repository, so a consumer workflow filters on the tag prefix, for example `web/`.

---

## 9. Identity and gates

### 9.1 GitHub App

Permissions named by the PDF: contents write, pull requests write, administration read. **[verify]** The ruleset sync
very likely needs administration **write**. An organisation-wide ruleset versus a per-repo one decides whether the
sync calls `/orgs/{org}/rulesets` or `/repos/{owner}/{repo}/rulesets`. The PDF says organisation-wide, the draft uses
the repo endpoint.

### 9.2 Token service

Out of scope as a design [D20, D23]. The concept needs it to provide: a short-lived installation token, issued only to
authenticated team members, with the private key held server-side. **[open]** how the service authenticates a
developer (an existing `gh` login checked against organisation membership is the obvious candidate), and what the
fallback is when it is down.

### 9.3 Rulesets and checks

- One ruleset for every released branch, master included: PR required, linear history, required checks, and the App
  as sole bypass actor so that it can push the release commit and its tag [6.1].
- Feature PRs still merge by auto-merge after the checks. The release is a direct push by the bypass actor, not a
  merge.
- The ruleset requires one aggregate check (6.6). `status-checks.yml` always runs, detects the changed components and
  runs the checks of their kinds as conditional jobs. A repo without PHP never waits for `PHP-CS-Fixer`, and adding a
  component never changes the ruleset **[verify]** that skipped jobs count as passed for a required check.
- **Squash and commit lint.** With squash merge the PR title becomes the commit. The check `Validate Conventional
  Commits` has to lint the PR title, and the repo setting for the squash commit title has to be set to the PR title
  **[verify]** the setting name and values. The local `commit-msg` hook then protects the working commits, not the
  history.

---

## 10. LLM steps

Commit message and changelog summary come from `provider_run_prompt`, which dispatches to the active provider and skips
when its binary is missing [D18]. Consequences:

- A skipped call must not skip validation: the generated or hand-written message always passes `git lint-commit`.
- The staged diff leaves the machine for the provider. A secret in a diff goes with it. The plugin should say so and
  offer a scrub or an opt-out.
- Inside a Claude Code session the step is redundant. It is useful for commands run from a plain shell.

---

## 11. Fit with agentic-os

The dispatcher resolves `app <domain> <command>` through the tier chain (project, plugins, framework) and runs the
first `modules/<domain>/<command>.sh` it finds. The plugin's `git` domain already works this way, with `PLUGIN_ROOT`
exported by bootstrap and plugin-local libraries.

- **Naming.** The dispatcher has no nested commands. `gh wf monorepo split` becomes `app git split` or a domain
  `monorepo` with `split`. **[open]**
- **Commands.** `start`, `commit`, `pr`, `release`, `split`, `rules-sync` join the existing seven. Each is one
  executable script with a `module.yaml` entry, and `lint modules` stays clean.
- **Hooks.** The `commit-msg` hook exists. A `pre-push` guard that refuses pushes to protected branches is declared and
  empty.
- **Override.** A project replaces a single command by dropping a script in its own tier.
- **Container.** A standing part of the project, see 11.1.

### 11.1 The container

The project notes record the container as a standing part of the plugin, with every developer on identical tool
versions (developer's answer in `architecture.md`). D3 names `app` as its entrypoint and D18 limits its content to
git-cliff, splitsh-lite and gh. An earlier lean of this paper, to drop the container for a `doctor` check, is withdrawn.

**Where the `Dockerfile` stands.**

- Kept: `node:22-bookworm-slim`, `gh`, git-cliff 2.8.0 and splitsh-lite 1.0.1 pinned by version, an arm64/amd64
  builder stage.
- Contradicting decisions: it still installs the Gemini CLI and Claude Code (D10, D18 say the plugin bundles no
  provider), and it copies `bin/gh-wf` as entrypoint, a file that does not exist since `app` replaces it (D3).
- Not yet pinned: the base image by digest, and the downloaded binaries by checksum. "Identical versions" holds only
  with both. `curl | bash` for the Claude installer goes with the provider removal.
- This host has no `docker`, `git-cliff` or `splitsh-lite` installed, only `gh`.

**Two models for what the container does**

| | M1 `app` runs inside the container | M2 the container only provides tools |
|---|---|---|
| Entrypoint | `app` (as D3 words it) | none; host `app` calls `git-cliff`, `splitsh-lite`, `gh` through the image |
| Needs in the image | bash, yq, jq, git, the framework and the plugin | the three tools, git, jq |
| Framework and plugin | mounted at the same absolute paths as on the host, or the tier chain breaks | stay on the host |
| Git hooks | cannot run in it; they run on the host git anyway | unaffected |
| Token for the App | passed in, or the service call is made inside | fetched on the host, passed as `GH_TOKEN` |
| Worktrees | the common git dir must be mounted too | same, per tool call |
| Node in the image | only for lint or publish | not needed |

M1 pulls the framework's tier chain, `yq`, the session environment and the plugin path (`../edotz.git-workflow` lies
outside the project) into the image. Whether the framework can run inside a container was not looked at by the
concept. M2 keeps all of that on the host and uses the image like a pinned toolbox. A small shim in the plugin library
(`tool_run git-cliff …`) would use the host binary when its version matches the pin, and fall back to the image
otherwise. This keeps the confirmed container and the identical versions, and needs no change of the dispatcher.
**Decided by the owner: M2, the container provides only the tools [input].** This revises the D3 wording "the container
entrypoint is `app`": the entrypoint is gone, `app` runs on the host. D18 already limits the content to the tools.

What M2 changes for the image and the plugin:

- **Image.** Only `git`, `gh`, `git-cliff` and `splitsh-lite`, run as `docker run <image> <tool> <args>`. No entrypoint,
  no Node, no `yq`, no `jq`, no `openssh-client`, no provider CLIs. The base need not be `node:22-bookworm-slim`: a
  slim base with glibc suffices, or musl builds of the tools **[verify]** the linkage of the splitsh-lite release binary.
- **Dockerfile fixes.** Remove the Gemini and Claude installs and the `bin/gh-wf` copy and entrypoint; pin the base by
  digest and verify each download by checksum.
- **Shim.** One plugin-library function runs a tool: the host binary when its version equals the pin, otherwise the
  image. The pinned versions live in one place, the plugin settings, and the image build reads the same values.
  Every command that needs a tool goes through the shim, never calls the binary directly.
- **Mounts per call.** The working directory and the repo's common git dir at their host paths, the host user and a
  writable `HOME`, and `GH_TOKEN` passed in from the host. Nothing else.
- **Where the shim is not used.** Git hooks and `lint-commit` stay on the host.

**Issues either model has to solve**

- **Worktrees.** A worktree's `.git` is a file pointing to a gitdir under the main repo. In a container that mounts
  only the current directory, git reports no repository. Mount the working directory and the repo's common git dir at
  their host paths, and mark them `safe.directory`.
- **User and home.** Run as the host user and set `HOME` to a writable path; the base image's `node` user does not
  match an arbitrary host uid, and `/root/.local/bin` is not readable by it.
- **Credentials.** With HTTPS pushes and an installation token (7.4), no SSH key or agent socket is needed, so
  `openssh-client` and the socket mount can go. If the token service authenticates through `gh` (Q-G), `~/.config/gh`
  is needed on the host only.
- **Distribution.** The image is built within the plugin, from its `Dockerfile`, on each machine, to speed up
  development [input]. No registry and no build workflow, so D19 stays intact. This makes "identical versions" depend
  on a reproducible build: with the base pinned by digest and the downloads by checksum, the same `Dockerfile` gives
  the same toolbox everywhere. Proposed on top of it: the shim builds the image on first use when it is missing, tags
  it with a hash of the `Dockerfile` and the pins so a change forces a rebuild, and a plugin command shows or forces
  the build. Whether a registry follows once the plugin is stable stays open, and nothing in the shim depends on it.
- **Cost.** Docker Desktop on macOS and bind-mount speed for splitsh-lite on large repos, and on WSL2 the repo must sit
  on the Linux filesystem. Docker itself becomes a prerequisite of every release.
- **libgit2.** `libgit2-dev` is in the image for building splitsh-lite. If the release binary is static it is not
  needed **[verify]**.

---

## 12. Migration

Proposed order, each step reversible until the split baseline:

1. GitHub App and token service; rulesets in report-only form next to the classic protection.
2. `release --dry-run` on a pilot single repo, compared against what release-please would produce.
3. `release --apply` on the pilot; remove its release-please, post-release and Stage Guard files.
4. `status-checks.yml` becomes the only generated workflow; the pre-flight gate shrinks accordingly.
5. Monorepo: split dry run, baseline per child (confirmed), then remove the split and sync workflows and the child pipelines.
6. Archive `edotz.monorepo-split-action`; retire `branch-protection` classic code after the last repo moved.

Changes in existing commands: `branch-cleanup` finds nothing merged after squash merges (D25), and `workflow-status`
reports commits since the last tag instead of commits ahead of a release branch.

---

## 13. Open question register

| ID | Question | Options | Lean |
|---|---|---|---|
| Q12 | How does a promotion reach the release branch | settled: no promotion, the development branch is released (6) [input] | |
| Q-A | Where does the CHANGELOG live | settled: on the released branch, so on master [input] | |
| Q-B | Release when `MAIN_BRANCH = RELEASE_BRANCH` | settled: this is the normal case (6) [input] | |
| Q-N | How is a maintenance line cut and released | a command that branches from a tag or SHA, or plain git | plain git, `release` runs on it (6.4) |
| Q-C | Baseline of existing child repos | force-push after dry run, or create children anew | force-push per child, confirmed |
| Q-D | One version or one per component | settled: one per component, no lockstep mode (6.6) [input] | |
| Q-Q | One "latest release" per repository with several components | link READMEs to the component's tag, or mark one component's Release as latest (8.1) | link to the component's tag; `--latest=false` on creation [verify] |
| Q-O | Format of the component declaration, and whether `kind` is needed | `.github/workflow.env` keys, or a structured file; `kind` as a source of defaults, or explicit `checks` and `version_files` only (Appendix B) | structured file; explicit lists, no `kind` |
| Q-P | Who defines the checks behind the aggregate check | the plugin's fixed check keys (D19), or commands the project declares (`toolchain`, turbo, terraform) with the plugin supplying commit lint and the aggregate | project-declared commands (Appendix B) |
| Q-R | Do JS components take their paths from the workspace graph | workspace graph and `turbo --affected`, or paths written in the declaration | workspace graph (6.6) |
| Q-E | Naming of split and rules sync | `app git <x>` or own domains | own domain `monorepo` |
| Q-F | What the container does | settled: tools only, with a host shim (11.1) [input] | |
| Q-M | Where the image is built and stored | settled for now: built within the plugin on each machine [input]; a registry later stays open | |
| Q-G | Token service authentication | `gh` login against org membership, other | `gh` login |
| Q-H | Pre-release handling | git-cliff, custom bump | verify first |
| Q-I | `STAGE` development relaxes what | the plan settles it [D21] | |
| Q-J | Package release (publish) as its own stage after the git release | settled: project-owned, starting from the Release (8.2, 8.3) [input] | |
| Q-K | Release notes content | git-cliff only, or with the LLM summary on top | summary optional, never required |
| Q-L | How the GitHub Release is created | CLI by API, CLI draft plus manual publish, tag workflow, release PR (8.1) | CLI by API, `--draft` as a variant |

---

## 14. To verify before the concept closes

1. Ruleset bypass modes (`always`, `pull_request`), and that an Integration actor can push a commit and a tag to a
   protected branch in one atomic push, which the release depends on (6.1).
2. App permission needed to create and update rulesets, and the organisation versus repository endpoint.
3. git-cliff pre-release support and the bump options for `0.x` versions.
4. The repo settings that make a squash merge use the PR title, and whether they can be set per repo through the API.
5. Whether `claude -p --bare` needs `ANTHROPIC_API_KEY` and ignores a subscription login, if the container ever runs it.
6. That splitsh-lite output for an unchanged monorepo state is byte-identical across machines and versions.
7. Whether `generate-readme-action` can be called as a local script or has to be ported.
8. That `gh release create` with `--target <sha>` creates the tag on a child commit with an installation token, and
   that `releases/latest` skips pre-releases and drafts.
9. Which events start workflows when the Release is created with the built-in token and with an App token.
10. Whether an App installation token can publish to the GitHub Packages npm registry, and how Packagist picks up a
    new tag.
11. The `version` field of `composer.json`, and the layout of `ext_emconf.php` for its writer (6.3).
12. That a job skipped by a condition counts as passed for a required status check, and that a workflow-level path
    filter leaves a required check pending (6.6, 9.3).
13. git-cliff with a path filter and a tag pattern per component: bump, changelog and the first release after a
    directory move (6.6). Whether `gh release create` can leave a Release out of "latest".

---

## Appendix A: the old commands and their successors

| Old | New |
|---|---|
| `/git:start` | `app git start` |
| `/git:commit` | `app git commit` |
| `/git:pr` | `app git pr` |
| `/git:release` (promote PR) | not needed, no promotion remains |
| release-please, `post-release`, `/trigger:release`, `/trigger:backport` | `app git release --dry-run`, `--apply` (includes the GitHub Release) |
| split action, `sync-to-monorepo` | `app git split` |
| `/git:setup-github` | `app git rules-sync`, and generation of `status-checks.yml` only |
| `/git:setup-workflow` (pre-flight) | reduced to config validation and drift of `status-checks.yml` |
| `/monitor:release`, `/monitor:action` | not needed, no release pipeline remains |


---

## Appendix B: the example project, `edotz.hh-web`

Read from `/home/ohoeft/workspace/edotz.hh-web` on 2026-11-02. Secrets files (`.env`, `.env.local`,
`google-auth.json`) were not opened.

### B.1 Structure

- A pnpm workspace with Turborepo. The root package `@edotz/hh-web` is private and has no version.
- `apps/web`: Next.js 16 frontend, package `hh-website`, version `0.1.0`.
- `apps/typo3-hub`: TYPO3 v12/13 as a headless CMS, run locally with DDEV. It has no `package.json`, its configuration is
  not committed and `src/` is empty.
- `packages/ui` (`@repo/ui`), `packages/api-client` (`@repo/api-client`, a typed client for the TYPO3 headless endpoint and
  the DIRS21 hotel API), and the config packages `tailwind-config`, `biome-config` and `typescript-config`, all private
  at `0.0.0`. `packages/playwright-utilities` is empty.
- The "two APIs" are external: the TYPO3 headless JSON endpoint and the DIRS21 API. Both are consumed by `@repo/api-client`,
  and the product notes forbid an API layer of the project's own. So there is no API component.
- There is no `.github` at the root, no workflow and no Terraform in the repository (it lives in a separate one today and moves into this repository, B.5). `apps/web/.github` and `apps/typo3-hub/.github` are
  empty directories, leftovers of the per-package manifest convention.
- The remote is `edotz/hh-web`, there is one branch, `master`, and eight commits. They are conventional, with the scopes
  `ui`, `api-client`, `aos`, `config`, `claude` and `project`.
- `commitlint.config.mjs` has a type list, lower-case scopes and no list of scopes. Turbo defines `build`, `lint` and
  `check-types`.
- `.agentic-os/project.yaml` of the project declares no plugin yet.

An earlier draft of this appendix assumed two API components. That was wrong and is removed.

### B.2 Components

| Component | What it is | Version file | Checks |
|---|---|---|---|
| `web` | the deployable frontend; `@repo/ui`, `@repo/api-client` and the config packages are its dependencies | `apps/web/package.json` | `turbo run lint check-types build --affected` |
| `typo3` | the deployable CMS | none committed yet; the `ext_emconf.php` of the site package once it exists | PHP checks once code exists |
| `infra` | Terraform for Hetzner with the nginx proxy and the application server; today a separate repository, moving into hh-web (B.5) | none by default | `terraform fmt`, `validate` |

The libraries are not components. They are private, at `0.0.0`, and have no consumer outside `web`. A change in them
releases `web`, which the workspace graph already knows.

Sketch, format open (Q-O):

```yaml
components:
  - name: web
    workspace: hh-website
    version_files: [apps/web/package.json]
  - name: typo3
    paths: [apps/typo3-hub]
  - name: infra
    paths: [infra]
    version: none
```

### B.3 What happens

| Change | Checks | Release |
|---|---|---|
| `fix(ui): …` in `packages/ui` | turbo marks `web` as affected, so its tasks run | `release web` gives `web/v0.1.1` |
| change under `apps/typo3-hub` | the `typo3` checks | `release typo3` gives `typo3/v0.1.0` |
| a Terraform change for a new nginx route | the `infra` checks | none if `infra` is unversioned; the apply is the project's |

A consumer workflow for deployment filters on `web/` or `typo3/` (8.3).

### B.4 What the real structure shows

- **The workspace graph replaces hand-written paths** for JavaScript components (Q-R). A `paths` list for `web` would have
  to repeat what `pnpm-workspace.yaml` and the package dependencies already say, and would drift.
- **Scopes are free.** The history uses `aos`, `config`, `claude` and `project`, which are not components. A scope list would
  reject them, and it would add nothing, since the release reads paths.
- **Component name and package name differ**, `web` against `hh-website`, so the declaration maps one to the other.
- **Checks as project commands (Q-P).** The project already defines its checks as turbo tasks and a `toolchain`. The plugin's
  fixed biome and php-cs-fixer callables would duplicate them. The plugin supplies commit lint and the aggregate check,
  and runs the commands the project declares.
- **A pilot with no migration.** No old workflow, no release-please, eight commits and one branch. It suits the dry run and
  the rulesets (migration steps 1 to 3) without touching any legacy.
- **TYPO3 has nothing to align yet.** Until a site package with `ext_emconf.php` exists, a `typo3` release commit holds
  only the CHANGELOG. Whether that is worth a release is open.
- **Lockfile.** Whether a version change in `apps/web/package.json` touches `pnpm-lock.yaml` has to be checked
  **[verify]**; if it does, the release commit includes it.

### B.5 The Terraform repository (`edotz.terraform`), moving into hh-web

Read on 2026-11-02; `.env` was not opened. The project is a proof of concept, and so is this repository.

- It is a separate repository, and `master` has no commit yet.
- It is a Docker toolbox for running Terraform locally: a `Dockerfile` (Go base image, Terraform, terrascan, terraform-docs
  and utilities installed by `.docker/*.sh`) and a `docker-compose.yaml` that mounts `src/`, the SSH agent and `~/.ssh`,
  and passes `HCLOUD_TOKEN` from `.env`.
- `he-modules/` is a clone of a third-party module repository (`Ujstor/terraform-hetzner-modules`) with its own `.git`.
  `src/examples/` holds the examples of that repository (cluster, server, firewall, load balancer, volumes, network,
  floating IP). `src/workspace/info` is a workspace with a `terraform.tfstate`. `src/main.tf` is empty. There is no
  configuration yet for the nginx proxy and the application server of hh-web.
- The apply runs by hand inside the container on a developer machine. There is no CI.

What this means for the model:

- **The Terraform moves into hh-web [input].** It becomes the `infra` component with `paths: [infra]`. A root `infra/` stays
  outside the `apps/*` and `packages/*` globs of the pnpm workspace, so it is a path component and not a workspace
  package. In the proof-of-concept phase it needs no version (`version: none`).
- **The repository has no commit yet**, so no history moves. What moves is the working tree, and the decisions below have
  to be made before it lands in hh-web.
- **A change that spans web and infra** (a new API route and its nginx route) becomes one PR, one set of checks and one
  merge. That was not possible across two repositories.
- **Apply is local today**, which matches P1. No consumer workflow is needed as long as that stays so. The question
  "apply on merge or from a tag" only arises with a pipeline.
- **The Terraform toolbox image** (`Dockerfile`, `docker-compose.yaml`, `.docker/`) is the project's own and independent of
  the plugin's tool image (11.1). The checks `terraform fmt` and `validate` are commands the project declares (Q-P),
  and a runner needs Terraform for them.
- **Before the move** (not part of the plugin design): hh-web's `.gitignore` has to cover `*.tfstate*`, `.terraform/`,
  `.terraform.d/`, `*.tfvars` and `.bash_history`, because a state file can hold secrets and the Hetzner token lives in
  `.env`. `he-modules` carries its own `.git`, so it would be recorded as an embedded repository; a pinned module
  source, a submodule or a vendored copy without `.git` are the alternatives. The `pre-commit` guard key that the plugin
  already declares could refuse state and env files, but that is a new feature and outside the model so far.
