# CONCEPT-git-workflow-plugin
Generated from CONCEPT-git-workflow-plugin.json, do not edit.

**Goal:** Settle the conceptual approach of the agentic-os git-workflow plugin that replaces the old single-repo and monorepo workflows.
**Scope:** edotz.git-workflow plugin: ci, bin/modules, bin/lib and the container image, as a concept with no implementation
**Role:** The plugin is the one place where the edotz projects get their git and GitHub workflow, a local and deterministic lifecycle behind `app git <command>` that replaces the old cascade of GitHub Actions.
**Input:** B-1
**Raw input:** notes/raw-input.md
**Status:** decided

## Abstract

The edotz git-workflow plugin replaces the old cascade of GitHub Actions with a local, deterministic workflow behind `app git <command>`: pull requests are gated on GitHub, a release is one commit with its tag made locally on master and pushed by a GitHub App, and a release branch follows master by fast-forward only.

### Background

The old single-repo and monorepo workflows rest on a chain of asynchronous Actions, backport PRs and the personal token of one developer; the plugin is the redesign that replaces them.

### Problem

The old approach causes many errors: up to five chained PRs and workflows per release, asynchronous backport PRs that conflict, no way to preview or fix a release locally, and every write right tied to one personal token.

### Constraints

- This is a conceptual approach only; nothing is implemented.
- The functionality ships inside agentic-os as a plugin, and the plugin neither chooses nor bundles an LLM provider.

### Goals

- Single repo and monorepo run start, commit, PR, promote, release (dry run and apply) and split through `app git <command>`.
- Each release is one atomic release commit with its tag, made locally.
- GitHub Actions only run the PR checks, and a GitHub App holds every release write right.
- The changelog is linear.
- The process has no pitfalls, and a developer in a young project can still push fast.

### Out of scope

- Any implementation.
- The design of the token service.
- The internals of generate-readme-action, the ide module and the vscode profiles.
- Publishing, deployment and provisioning after the release, which belong to the consuming project.

### Audience

The edotz developers working in agentic-os sessions; one developer is in charge today.

### Approach

A feature branch becomes a PR that GitHub gates with one aggregate check and squash-merges onto master; in a project's development phase developers may push to master directly. A release is made on master as one commit with version files, changelog and README plus its tag. A dry run previews it, and the GitHub App, the only actor that releases, pushes it. The release branch named in RELEASE_BRANCH follows by a separate fast-forward promote. Legacy branches have no relation to master and change by PR. A monorepo is an integrated product of components, each versioned and released on its own. Tools run from a pinned image through docker.

### Measures

- Squash merge on master with a conventional PR title in the production phase; in the development phase developers push to master directly; STAGE switches the master ruleset between the two.
- Rulesets replace the classic branch protection. The App makes the release commit, the tag and the promote in both phases. In production no human pushes to master, and the release branch takes no human push in either phase.
- A token service gives the CLI short-lived installation tokens of the app.
- `release --dry-run` previews version, notes and the files that change; `release --apply` writes version files, CHANGELOG and README into one release commit on master with its tag, pushes both as the App and creates the GitHub Release; `--draft` leaves it unpublished.
- A release needs a green minimum check on HEAD: commit lint of the commits since the last tag plus the quick checks the project declares. The local commit-msg lint guards every commit.
- `promote` fast-forwards the release branch to the release commit of a release, identified by its tag, never to the head of master, and does nothing else.
- Legacy branches stay separate, change by PR (cherry-picks allowed) and are released as master is.
- A component has its own version and the tag <component>/vX.Y.Z (vX.Y.Z for a single repo). The bump comes from its paths, non-library components are version: none, and only a component with split: yes is split with splitsh-lite and pushed from the developer machine.
- The plugin ends at the release: publishing, deployment and provisioning are consumers of the GitHub Release in the consuming project.
- Commit message and changelog summary come from `provider_run_prompt` on the host session.
- The image carries only git, gh, git-cliff and splitsh-lite. It is built by docker compose with its config in .docker, pinned by digest and checksum. Modules run the tools through docker with identical host and container paths and the token passed per call; whether by docker exec in a running container or by an ephemeral container per call is left to the plan.
- Commands are `app git start`, `commit`, `pr`, `release`, `promote`, `split` and `rules-sync`, beside the seven existing ones: lint-commit and worktree stay, workflow-setup shrinks to config validation and status-checks.yml, the plumbing of branch-protection becomes rules-sync, workflow-status and branch-cleanup adapt to squash and promote, and run-status folds or goes.
- All old CI except status-checks.yml is removed, and the release branch is read from RELEASE_BRANCH.
- A pre-push guard hook runs the minimum check locally when a developer pushes, so a broken direct push is found at once.
- In a repository with several components every component release is created with --latest=false, and READMEs and badges link to explicit component tags; a repository with one component keeps the normal latest release.

### Why

The old chain breaks at any link and cannot be fixed locally; a local release can be previewed and corrected before GitHub sees it. The App's short-lived tokens remove the dependence on one person, and squash merge gives a linear changelog without history cleanup. Releasing on master aligns the version files in one commit, and the fast-forward release branch still shows how the project evolved. Direct pushes in the development phase keep a young project fast, while the minimum check and the App-only release keep the release itself safe.

### Alternatives

- Replaying master commits onto the release branch: dropped for fast-forward only.
- The release commit only on the release branch: rejected because master could no longer fast-forward it.
- No standing release branch and no promotion, as the white paper proposes: not chosen, because the release branch shows how the project evolved.
- Maintenance lines cut on demand instead of legacy branches: not chosen.
- Rebase merge on master: keeps every commit but makes the developer care about commit hygiene.
- A workflow on tag push or a release PR to create the GitHub Release: rejected, they add a generated file or an asynchronous hop.
- A host-binary shim with a docker fallback: not chosen, modules always call docker.
- Personal tokens, a key in the container or SSH for the split push: rejected for a token service.
- Bundled provider CLIs or LLM steps inside the container: dropped, because the provider belongs to agentic-os.
- A GitHub Action on every push to master: not chosen, a local pre-push guard gives immediate feedback and adds no workflow.

### Risks

- The release commit reaches master without CI, so the dry run and the minimum check are its only gate.
- A direct push to master in the development phase is unreviewed; the phase switch returns master to PRs once the project matures.
- Several GitHub behaviours the release depends on are unverified (an Integration bypass with an atomic push of commit and tag, gh release create with an App token and with --latest=false, skipped jobs counting as passed); the plan verifies them first.
- The first split of an existing child repository needs a force push; a confirmed dry run per child is required.
- Every machine that releases needs Docker, and whether the container is long-running or ephemeral is undecided.
- branch-cleanup finds no merged branches after squash merges, so its detection is carried to the plan.
- The GitHub App, the token service and the local README generator have no design or code yet, and releases depend on them.
- The project context (product, identity, architecture and the root rule) still holds the old merge-commit, gh-wf and entrypoint wording; the plan updates it.

### Success

- A release can be previewed and corrected locally before anything reaches GitHub.
- No backport PR, no personal token and no cascade of workflows remain.
- In the production phase the master changelog has one entry per merged PR, in order.
- The release branch shows each released state of master as a fast-forward line.

### Still open

- Whether the modules use docker exec in a running container (one per machine or one per repository) or an ephemeral container per call.
- The baseline force push of existing child repositories.
- The format of the component declaration.
- Which quick checks join the minimum check and the aggregate check.
- Whether JS components take their paths from the workspace graph.
- Pre-release handling.
- How the token service authenticates a developer and how it is designed.
- Whether the release notes carry an LLM summary.
- The writers for the version files.
- The naming of split and rules-sync.
- How the README is generated locally.
- How workflow-status and branch-cleanup change.
- How the rulesets replace the classic protection code.

## Capabilities

- Start a branch or worktree from the main branch and commit with a validated conventional message, optionally drafted by the host provider.
- Open a PR with a conventional title and gate it through one aggregate status check.
- Preview a release locally (version, notes, changed files) and apply it as one release commit with its tag and a GitHub Release, pushed by the GitHub App.
- Require a green minimum check on HEAD before a release.
- Promote a released master to the release branch by fast-forward only, and keep legacy branches separate, changed by PR.
- Version and release each component of a monorepo on its own, with tags <component>/vX.Y.Z derived from its paths.
- Split a component marked split: yes into its own repository with splitsh-lite.
- Apply the GitHub rulesets and the STAGE phase through rules-sync, with the App as the bypass actor.
- Obtain short-lived App installation tokens from a token service.
- Run git-cliff, splitsh-lite and gh from a pinned image built by docker compose, through docker.
- Run the minimum check locally on push through a pre-push guard.

## Sources

- 260903-git-workflow.md: Role new, the primary draft: local CLI, splitsh-lite split, git-cliff changelog, rulesets, atomic release commit, container image; read in full. (verified)
- docs/git-workflow-monorepo/SKILL.md: Role old: the monorepo workflow with split action, childrepo release train and sync-to-monorepo backport, which the plugin replaces; read in full. (verified)
- docs/git-workflow-single/SKILL.md: Role old: the single-repo workflow with release-please, post-release backport and STAGE split, which the plugin replaces; read in full. (verified)
- docs/git-workflow: Role old: the old reference docs and slash command table (commands, lifecycle, preflight, workflow-env, generated-artifacts, callable-workflows, repo-details); all seven read. (verified)
- .github/workflows: Role old: the old CI, named in the input as .github/workflow; all 6 files read, the callables use the personal token NPM_AUTH_TOKEN. (verified)
- .claude/session/a24bcf21/260903_edotz_gitworkflow.pdf: Role context: the German analysis behind the draft, with the GitHub App migration, ruleset design and its open questions; read in full, 12 pages. (verified)
- /home/ohoeft/workspace/edotz.claude-code/bin/adapters/claude/agent.sh: Named in dialog (gap G4): the Claude adapter's adapter_run_prompt (claude -p, model haiku) and adapter_run_agent; read together with lib/provider.sh, whose provider_run_prompt dispatches to it. (verified)
- bin/modules, bin/lib, Dockerfile: Named in dialog (gap G3): the git module scripts, templates, hooks.yaml, github.sh, worktree.sh and the Dockerfile, read for what the plugin does today; the ide scripts were not read. (verified)
- 261102-git-workflow-whitepaper.md: Role new: the white paper, the discussion basis with the owner's positions of 2026-11-02, the component model, the container models and the open question register; read in full. (verified)
- 261102-git-workflow-process.md: Role new: the possible process for a single repository and a monorepo, with the daily and release loops, guards and failure table; read in full. (verified)
- 2611102-git-workflow-evaluation.md: Role context: an evaluation of the concept against complexity, monorepo support and command centralisation; read in full. (verified)
- /home/ohoeft/workspace/protect.technikschutz: Named in dialog: the docker-compose files, the .docker directory, the Dockerfile stages and .env.defaults as the pattern for the image definition; the Dockerfile was read in part and .env was not opened. (unverified)
- .agentic-os/project/concepts/261102-git-workflow-plugin-review.md: Role context: a review of the first draft of the concept against the white paper; read in full. (verified)
- .agentic-os/project/concepts/261102-git-workflow-plugin-review-2.md: Role context: a review of the decided concept, with the promote race, the container lifecycle and the late discovery of a broken direct push; read in full. (verified)

## Not looked at

- The detected scope ci has no declaration and so no memory.
- The path .github/workflow named in the input does not exist; .github/workflows was read in its place.
- The ide scripts, the commit-msg hook script and bin/config/env.defaults were not read in full.
- The 56 web references cited in the PDF were not followed.
- Whether agentic-os provides a way to run the framework inside a container was not looked at; the docker exec model makes it moot.
- The white paper cites three repositories that were not followed: edotz.monorepo-split-action, edotz.hh-web and edotz.terraform.
- The 13 verify claims of the white paper were not checked against current documentation, for example the ruleset bypass of an Integration actor and gh release create with a target.
- The bodies of the seven existing git commands were not read in full; their fates are judged from the registry, the file headers and the architecture notes.
- protect.technikschutz was read for its compose and .docker layout only; its .env was not opened.

## Questions

- Q1 What is the name of this concept? (Every call of the concept needs the name.) -> D1
- Q2 How do the draft's linear history on 2.x/1.x and the merge-commit-only rule fit together? (The draft and the old skills disagree on the merge policy.) -> D2
- Q3 Which command surface does the plugin expose, given that the framework app replaces bin/gh-wf? (The draft names the tool gh wf, gh-wf and git-wf.) -> D3
- Q4 What replaces the personal access token of ohoeft for runner authentication, monorepo splits and PR creation? (The personal token is the administrative bottleneck of the old design.) -> D4
- Q5 Who is the bypass actor on 2.x and 1.x once the GitHub App replaces the personal token? (The draft names ohoeft by user ID, the PDF names the app and ohoeft.) -> D5
- Q6 How does the local CLI obtain the GitHub App's installation token? (The split push, PR creation and the release push all need the app identity.) -> D6
- Q7 Does D2 stand for master, or does the linear history of the PDF apply to it too? (The PDF requires linear history on master, the draft only on the release branches.) -> D7
- Q8 What does the linear changelog require of master? (It decides whether PRs merge by rebase, squash or merge commit.) -> D8
- Q9 How does a promotion reach 2.x after the first release commit, without backport PRs? (After the release commit master no longer is a fast-forward ancestor of 2.x.) -> D9
- Q10 Which LLM provider does the plugin call headlessly for commit messages and the changelog summary? (The draft bundles the claude and gemini CLIs in the image.) -> D10
- Q11 Which merge strategy does master use for PRs? (D7 and D8 name the goal but not the strategy.) -> D11
- Q12 By which mechanism does a promotion reach 2.x? (D9 names the criteria but not the mechanism; the developer answered only where the target branch comes from (D16).) -> D27
- Q13 What stays of the old CI and the STAGE concept? (The draft keeps only status-checks.yml; the developer had not settled the Stage Guard and STAGE.) -> D17
- Q14 Where do the steps that need an LLM, the commit message and the changelog summary, run? (provider_run_prompt skips when the provider binary is missing, and the container entrypoint is app.) -> D18
- Q15 Which parts of the old CI does the plugin remove? (Four callables use the personal token and the release flow no longer needs release-please or backport PRs.) -> D19
- Q16 What is the purpose of this work, the problem it answers? (The abstract needs its background and problem.) -> D14
- Q17 What does the work have to reach, so that it can be told to be done? (The abstract needs its goals.) -> D15
- Q18 What does this concept not cover? (The abstract needs its constraints and what is out of scope.) -> D20
- Q19 Where does the target branch of a promotion come from? (The draft passes it as --target 2.x.) -> D16
- Q20 What does the development phase of STAGE relax on master? (D17 keeps STAGE as a switch without saying what it switches.) -> D29
- Q21 How is the README generated locally in the release commit? (generate-readme-action runs only as a GitHub Action today.) -> D22
- Q22 How is the token service designed? (D6 chooses a token service without a design.) -> D23
- Q23 Which pre-release flags and tag format does a release use, for a single repo and for monorepo packages? (The PDF names --pre=<channel> and packages/object/v2.1.0-beta.1.) -> D24
- Q24 How do workflow-status and branch-cleanup change after squash merge and replay? (Both rely on rev-list counts and git branch --merged.) -> D25
- Q25 How do the rulesets replace the classic branch protection code? (github.sh and workflow-setup only know the classic protection API.) -> D26
- Q26 How do legacy branches live next to a fast-forward-only release branch? (The concept never decided them, and a legacy branch cannot be fed by promotion.) -> D31
- Q27 Where is the release commit made? (Fast-forward promotion needs the release commit on master.) -> D28
- Q28 Who may push the release commit, the tag and the promote? (Master now receives the release commit directly.) -> D30
- Q29 Where does the minimum check for quality run? (A direct push has no CI, and the release guard needs a check on HEAD.) -> D32
- Q30 Does master carry the version? (The release commit is on master, and an earlier decision said master need not track the version.) -> D33
- Q31 What does the container do? (The white paper records the model M2 against the entrypoint wording of an earlier decision.) -> D34
- Q32 Do the modules use a host binary or docker only? (The white paper proposes a shim with a host-binary fallback.) -> D35
- Q33 How is the image defined and how do the modules call it? (Compose and a .docker directory are the pattern of the example project.) -> D55
- Q34 How does the container lifecycle work? (A running container mounts its directories at start, and the modules work in many repos and worktrees.) -> D55
- Q35 What is the versioning unit and the tag format? (A monorepo is an integrated product of components, not an unversioned staging area.) -> D38
- Q36 Where does the plugin end? (Publishing, deployment and provisioning follow the release.) -> D39
- Q37 How is the GitHub Release created? (The READMEs link to releases/latest, and release-please created the Release before.) -> D40
- Q38 Which commands does the plugin expose, and what happens to the seven existing ones? (The existing seven phase out the old approach.) -> D41
- Q39 How does GitHub's single latest release per repository work with several components, and how do the READMEs link to a component's release? (GitHub has one latest release per repository.) -> D56
- Q40 How is the baseline of existing child repositories done? (Their history shares no SHAs with a splitsh-lite history, so the first push needs a force push.) -> D43
- Q41 What is the format of the component declaration, and does it need a kind? (It replaces PACKAGES_DIR and the workflow.env per package.) -> D44
- Q42 Which quick checks join the minimum check and the aggregate check? (The project declares them, and the plugin supplies commit lint and the aggregate.) -> D45
- Q43 Do JS components take their paths from the workspace graph? (turbo --affected knows what changed.) -> D46
- Q44 How are pre-releases handled? (Whether a pre-release is tag only or makes a commit, and whether git-cliff counts pre-release versions, is unchecked.) -> D47
- Q45 How does the token service authenticate a developer? (A gh login against organisation membership is the candidate, and the fallback when the service is down is open.) -> D48
- Q46 Do the release notes carry an LLM summary? (The summary is optional and never required in the white paper.) -> D49
- Q47 Which writers align the version files? (package.json, composer.json and ext_emconf.php need one writer per file kind, read back after writing.) -> D50
- Q48 Do split and rules-sync live in the git domain or in their own domain? (The dispatcher has no nested commands.) -> D51
- Q49 What does promote fast-forward the release branch to? (Master can move after the release commit, so a head-of-master target would carry unreleased commits.) -> D52
- Q50 Where does early feedback on a direct push to master come from? (The minimum check runs at release, so a broken direct push would surface late.) -> D54

## Decisions

- D1 [decided] The concept name -> git-workflow-plugin (Taken from the goal: the new agentic-os git workflow plugin.; owner, 2026-10-20, concept-only)
- D2 [superseded] History policy of master and the release branches -> Split by branch: master takes PRs with merge commits only; 2.x and 1.x have linear history, promotion goes onto them and the atomic release commit sits on top, both by the bypass actor. (Keeps the individual conventional commits on master for git-cliff and gives the release branches the linear history of the draft. Its master half is superseded by D11.; owner, 2026-10-20, durable) superseded by D11
- D3 [superseded] Command surface of the plugin -> app git <command>; the names gh-wf, gh wf and git-wf are dropped and the container entrypoint is app. (The framework app replaces bin/gh-wf and the plugin's git module already lives under app git.; owner, 2026-10-20, durable) superseded by D41
- D4 [decided] Replacement of the personal access token -> The current process, in which ohoeft's personal access token is used for runner authentication, monorepo splits, and creating pull requests, will be completely replaced by an internal GitHub App. (The developer's words, which the PDF repeats: a personal token binds the process to one person and one token lifetime.; owner, 2026-10-20, durable)
- D5 [superseded] Bypass actor on 2.x and 1.x -> The GitHub App is the only bypass actor (actor_type Integration, mode always); master has no bypass for anyone. ohoeft as a user ID is dropped. (The personal token is replaced completely (D4); the PDF lists the app and ohoeft, the developer chose the app alone.; owner, 2026-10-20, durable) superseded by D30
- D6 [decided] How the CLI obtains the app token -> A token service issues short-lived installation tokens to the CLI, so the app's private key never reaches a developer machine. (The PDF names a GitHub App Token Service in its phase 1; the developer chose it. The service design is not specified.; owner, 2026-10-20, durable)
- D7 [decided] Goal for the changelog -> What I need is a linear changelog, adapt the rest to this goal. (The developer's words, given instead of an option; it is a requirement for the history and the release commit.; owner, 2026-10-20, durable)
- D8 [decided] Ease of development -> The development should be easy and the developer concern should not be the incorporation of his changes. (The developer's words, given instead of an option; the tool carries the incorporation, not the developer.; owner, 2026-10-20, durable)
- D9 [superseded] Criteria for the promotion and release process -> I want a process with no pitfalls. If master tracks the new version, nice, if not, ok. The old approach causes a lot of errors and problems. I want to get rid of this. Today only one developer is in charge. (The developer's words, given instead of an option; master does not have to track the version, and the cascade of the old approach has to go.; owner, 2026-10-20, durable) superseded by D33
- D10 [decided] LLM provider for commit messages and the changelog summary -> The LLM provider mentioned in the raw concept is just an example; we are using agentic-os and ship the functionality within agentic-os as a plugin. The plugin neither chooses nor bundles an LLM CLI. (The developer's words; the provider side belongs to agentic-os. How a plugin makes a headless provider call was looked at afterwards: provider_run_prompt, see D18.; owner, 2026-10-20, durable)
- D11 [superseded] Merge strategy of master -> Squash merge on master: one PR, one linear commit and one changelog entry taken from the PR title. master, 2.x and 1.x all have linear history, and the promotion and the atomic release commit go onto 2.x and 1.x by the bypass actor. (The developer chose it after the recommendation from D7 and D8. Without release-please the old reason for merge-commit-only history is gone; branch-cleanup's merged-branch detection has to change (D25).; owner, 2026-10-20, durable) superseded by D29
- D12 [superseded] Mechanism of the promotion to 2.x -> The CLI replays the new master commits onto 2.x; the release commit with version, CHANGELOG and README exists only on 2.x and its tag, and master's README carries no version, only releases/latest links and version badges. (Derived from D9: master need not track the version, and the local atomic release commit with its tag stays, unlike a release PR with a tag after an async merge. Unconfirmed: the developer answered with D16 instead of choosing. A replay conflicts if a master commit touches files the release commit owns, and workflow-status would have to compare patch IDs.; claude, 2026-10-20, durable) superseded by D27
- D13 [superseded] What stays of the old CI and the STAGE concept -> Not decided at the time: the draft keeps only status-checks.yml; the Stage Guard and the dev/prod STAGE split were open. (The developer said they were searching for the best fit and that a project start brings many changes. Answered by D17 for STAGE and D19 for the old CI.; owner, 2026-10-20, durable) superseded by D17
- D14 [decided] Purpose of the work -> A reliable release process: replace the cascade of GitHub Actions, the personal token and the asynchronous backport PRs with a local, deterministic workflow run through agentic-os that can be fixed before anything reaches GitHub. (The developer confirmed the recommendation drawn from D9 and the PDF analysis.; owner, 2026-10-20, durable)
- D15 [decided] Goal of the work -> Local release, GitHub only gates: single repo and monorepo run start, commit, PR, promote, release (dry run and apply) and split through app git <command>; each release is one atomic release commit with its tag; GitHub Actions only run the PR checks and the GitHub App holds every write right. (The developer confirmed the recommendation; it is done when no backport PR, no personal token and no cascade remain in the concept.; owner, 2026-10-20, durable)
- D16 [decided] Where the target branch of a promotion comes from -> The Release branch is determined via the env variable RELEASE_BRANCH. (The developer's words, given as the answer to the promotion mechanism; it drops the --target flag of the draft. How the promotion reaches the branch stays open (Q12).; owner, 2026-10-20, durable)
- D17 [decided] What stays of the STAGE concept and the Stage Guard -> STAGE stays as a project-phase switch for the master ruleset only: a lighter development phase and the full D5 rules in production. The Stage Guard goes. (The developer confirmed the recommendation, matching their note that a project start brings many changes. D5 removes the master bypass that STAGE used to toggle, and a promotion makes no PR to the release branch that the Stage Guard could block.; owner, 2026-10-20, durable)
- D18 [decided] Where the LLM steps run -> The commit message and the changelog summary come from provider_run_prompt on the host session, where the provider already runs; the container does only the deterministic tools (git-cliff, splitsh-lite, gh) and needs no provider binary and no LLM credentials. (The developer confirmed the recommendation. provider_run_prompt dispatches to the adapter of the active provider and skips when the binary is missing (bin/lib/provider.sh, adapters/claude/agent.sh).; owner, 2026-10-20, durable)
- D19 [decided] Which parts of the old CI the plugin removes -> All but the PR checks. Removed: the callables for release-please, post-release, merge-split-repo and sync-to-monorepo, the generated release and split callers, and release-please-config.json. Kept: status-checks.yml (commit-lint, biome, php-cs-fixer, shellcheck) as the only GitHub Action. (The developer confirmed the recommendation, as in the draft; all four removed callables use the personal token.; owner, 2026-10-20, durable)
- D20 [decided] What the concept does not cover -> Concept only, designs left out: any implementation, the design of the token service, the internals of generate-readme-action, the ide module and the vscode profiles are out of scope. The concept names what each of them must provide. (The developer confirmed the recommendation; it keeps the stated limit of a conceptual approach with no implementation.; owner, 2026-10-20, concept-only)
- D21 [superseded] What the development phase of STAGE relaxes on master -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only) superseded by D29
- D22 [decided] How the README is generated locally in the release commit -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only)
- D23 [decided] How the token service is designed -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only)
- D24 [superseded] Pre-release flags and tag format for a single repo and monorepo packages -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only) superseded by D38
- D25 [decided] How workflow-status and branch-cleanup change after squash merge and replay -> The plan settles it. (A detail that depends on the chosen approach and on Q12; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only)
- D26 [decided] How the rulesets replace the classic branch protection code -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only)
- D27 [decided] How a promotion reaches the release branch -> Promotion is fast-forward only and covers master to the release branch only; the release branch stays so that it shows the evolution of the project. (The developer's words: the release branch helps to see the evolution of a project. It supersedes the replay proposed in D12.; owner, 2026-11-02, durable)
- D28 [decided] Where the release commit is made -> On master; the release branch moves later by a separate promote command that fast-forwards it. (The developer chose it over moving the branch in the same push: master can lead the release branch, and a release commit only on the release branch would break the fast-forward rule.; owner, 2026-11-02, durable)
- D29 [decided] What the development phase of STAGE relaxes on master -> In the development phase master takes direct pushes by developers and requires no checks; in the production phase a PR with the aggregate check and squash merge is required. Master, the release branch and the legacy branches keep a linear history. (The developer prefers to push to master directly when building a project from scratch, because the code changes very often; the release stays App-only in both phases. It supersedes D11 and D21.; owner, 2026-11-02, durable)
- D30 [decided] Who may make the release commit, the tag and the promote -> The GitHub App is the only actor that makes the release commit, the tag and the promote, in both phases. In production no human pushes to master; in development developers push to master only; the release branch takes no human push in either phase. (The developer confirmed the recommendation after the comparison of flexibility and standards; it revises D5, which gave master no bypass.; owner, 2026-11-02, durable)
- D31 [decided] How legacy branches live next to a fast-forward-only release branch -> A legacy branch has no relation to master any more; it changes only by a PR that targets it, which may carry cherry-picked commits, and it gets the release-branch ruleset: PR required, linear history, the App as sole bypass for the release commit and tag. (The developer chose reading B after saying that cherry-picks are fine; promotion cannot feed a legacy branch because it has diverged from master. That the App makes the release on a legacy branch comes from the white paper and was not separately confirmed.; owner, 2026-11-02, durable)
- D32 [decided] Where the minimum check for quality runs -> The minimum check runs at release: release --dry-run and --apply require it green on HEAD, made of the commit lint of the commits since the last tag plus the quick checks the project declares. The local commit-msg lint stays the floor for every commit, and direct pushes need no CI. (The developer asked for a minimum check and followed the recommendation of reading 2: GitHub cannot gate a direct push with CI, and the release is the point where the App pushes unchecked. Which quick checks is left to the plan.; owner, 2026-11-02, durable)
- D33 [decided] Whether master carries the version -> Master carries the version through the release commit, and the release branch follows by the separate promote. (The developer confirmed it as the consequence of making the release commit on master; it supersedes D9.; owner, 2026-11-02, durable)
- D34 [decided] What the container does -> The image carries only git, gh, git-cliff and splitsh-lite; it has no entrypoint, and app runs on the host. (The developer's choice of M2 recorded in the white paper, confirmed by the answer that the local modules execute docker commands; it replaces the entrypoint wording of D3.; owner, 2026-11-02, durable)
- D35 [decided] Whether the modules use a host binary or docker only -> Every tool call goes through docker, with no host-binary fallback, built by one library function. (The developer chose option A: it is simpler and guarantees identical versions; Docker is required on every machine that releases.; owner, 2026-11-02, durable)
- D36 [superseded] How the image is defined and how the modules call it -> The image is defined with docker compose and a dedicated .docker config directory; compose serves to build the images and to give a configuration overview. Modules run the tools with docker exec in a running container with identical host and container paths and the token passed per call. The base image is pinned by digest and each download by checksum. (The developer's words, modelled on the project protect.technikschutz; it replaces the build on first use with a hash tag that the white paper proposed.; owner, 2026-11-02, durable) superseded by D55
- D37 [superseded] How the container lifecycle works -> The plan settles it: one container per machine or one per repository. (A detail that depends on the chosen approach; the developer did not know yet and chose to carry it after the pros and cons were listed.; owner, 2026-11-02, concept-only) superseded by D53
- D38 [decided] The versioning unit and the tag format -> Each versioned component has its own version and is released on its own with the tag <component>/vX.Y.Z (vX.Y.Z for a single repo, which is one component at the root). The bump comes from the commits that touch its paths, components that make no library can be version: none, and only a component with split: yes is split. (The developer confirmed the recommendation from the white paper; it supersedes the tag-format part of D24, and the pre-release flags stay with the plan.; owner, 2026-11-02, durable)
- D39 [decided] Where the plugin ends -> The plugin ends at the release: tag, release commit, notes and GitHub Release. Publishing, deployment and provisioning belong to the consuming project and start from the Release; the plugin may document an example workflow for node packages. (The developer confirmed it; it keeps D19 intact.; owner, 2026-11-02, durable)
- D40 [decided] How the GitHub Release is created -> release --apply creates the GitHub Release as the App in the same run, a repeated --apply creates only what is missing, and --draft leaves it unpublished for a person to publish. (The developer followed the recommendation: no asynchronous hop and no generated file per repo; a Release created with an App token starts consumer workflows, which is still to be verified.; owner, 2026-11-02, durable)
- D41 [decided] The command surface and the fate of the seven existing commands -> app git <command>; the names gh-wf, gh wf and git-wf stay dropped. New: start, commit, pr, release, promote, split and rules-sync. Existing: lint-commit and worktree stay; workflow-setup shrinks to config validation and status-checks.yml; branch-protection becomes rules-sync on its plumbing; workflow-status and branch-cleanup adapt to squash and promote; run-status folds or goes. (The developer confirmed the list and the fate of the seven, with the details left to the plan; it supersedes D3, whose container wording D34 replaces.; owner, 2026-11-02, durable)
- D42 [superseded] How GitHub's single latest release per repository works with several components -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry all detail questions to the plan.; owner, 2026-11-02, concept-only) superseded by D56
- D43 [decided] How the baseline of existing child repositories is done -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry all detail questions to the plan.; owner, 2026-11-02, concept-only)
- D44 [decided] The format of the component declaration -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry all detail questions to the plan.; owner, 2026-11-02, concept-only)
- D45 [decided] Which quick checks join the minimum check and the aggregate check -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry all detail questions to the plan.; owner, 2026-11-02, concept-only)
- D46 [decided] Whether JS components take their paths from the workspace graph -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry all detail questions to the plan.; owner, 2026-11-02, concept-only)
- D47 [decided] How pre-releases are handled -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry all detail questions to the plan.; owner, 2026-11-02, concept-only)
- D48 [decided] How the token service authenticates a developer -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry all detail questions to the plan.; owner, 2026-11-02, concept-only)
- D49 [decided] Whether the release notes carry an LLM summary -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry all detail questions to the plan.; owner, 2026-11-02, concept-only)
- D50 [decided] Which writers align the version files -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry all detail questions to the plan.; owner, 2026-11-02, concept-only)
- D51 [decided] Whether split and rules-sync live in the git domain or in their own domain -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry all detail questions to the plan.; owner, 2026-11-02, concept-only)
- D52 [decided] What promote fast-forwards the release branch to -> promote fast-forwards the release branch to the release commit of a release, identified by its tag, and never to the head of master, so commits pushed to master after the release cannot reach the release branch. (Review 2 found that a head-of-master target would carry unreleased commits when developers push directly in the development phase; the developer recorded the recommendation. It refines D28.; owner, 2026-11-02, durable)
- D53 [superseded] How the container lifecycle works -> The plan settles it: one container per machine, one per repository, or an ephemeral container per call. Docker stays required, and D35 and D36 stand. (Review 2 argued for ephemeral runs; the developer recorded the recommendation to add them as a third candidate and to keep docker only and docker exec as decided. It supersedes D37.; owner, 2026-11-02, concept-only) superseded by D55
- D54 [decided] Where early feedback on a direct push comes from -> A pre-push guard hook runs the minimum check locally when a developer pushes, so a broken direct push is found at once; no GitHub Action runs on push. (Review 2 found that a broken direct push would surface only at release; the developer recorded the recommendation of a local guard: the pre-push key is registered and has no hook yet, and it keeps the workflow local-first and the single status-checks.yml.; owner, 2026-11-02, durable)
- D55 [decided] How the modules call the tool image -> Modules always run the tools through docker, with no host-binary fallback, identical host and container paths and the token passed per call. The plan settles whether that is docker exec in a running container (one per machine or one per repository) or an ephemeral container per call. The image is defined with docker compose and a .docker config directory, compose builds the images and gives the configuration overview, and the base image is pinned by digest and each download by checksum. (Review 3 found that D53 listed an ephemeral container as a candidate while saying D36 stands, and D36 names docker exec. The developer chose option c: reword both so that docker is fixed and the plan picks exec or ephemeral. It supersedes D36 and D53; D35 stands.; owner, 2026-11-02, durable)
- D56 [decided] How one latest release per repository works with several components -> In a repository with several components every component release is created with --latest=false, and READMEs and badges link to explicit component tags (releases/tag/<component>/vX.Y.Z), never to releases/latest. A repository with one component keeps the normal latest release. Whether gh release create supports --latest=false is checked in the plan. (The developer followed review 3 with the fix that the rule applies only to repositories with several components, so that a single-component repository keeps a working releases/latest. It matches the lean of the white paper and supersedes D42.; owner, 2026-11-02, durable)

## Revisions

- 2026-11-02 promote targets the release commit by its tag and never the head of master. (affects Q49, D28, D52) -- Review 2: a head-of-master target would carry unreleased commits onto the release branch. (owner)
- 2026-11-02 The container lifecycle candidates now include an ephemeral container per call. (affects Q34, D37, D53) -- Review 2 argued for ephemeral runs; D35 and D36 stand. (owner)
- 2026-11-02 A local pre-push guard runs the minimum check on push. (affects Q50, D32, D54) -- Review 2: a broken direct push would surface only at release. (owner)
- 2026-11-02 Docker is fixed for the tool calls, and the plan chooses between docker exec in a running container and an ephemeral container per call. (affects Q33, Q34, D36, D53, D55) -- Review 3: D53 listed an ephemeral container while saying D36, which names docker exec, stands. (owner)
- 2026-11-02 Component releases in a repository with several components use --latest=false and READMEs link to explicit component tags. (affects Q39, D42, D56) -- Review 3: GitHub has one latest release per repository; a single-component repository keeps the normal latest release. (owner)
