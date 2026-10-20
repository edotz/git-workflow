# CONCEPT-git-workflow-plugin
Generated from CONCEPT-git-workflow-plugin.json, do not edit.

**Goal:** Settle the conceptual approach of the agentic-os git-workflow plugin that replaces the old single-repo and monorepo workflows.
**Scope:** edotz.git-workflow plugin: ci, bin/modules, bin/lib and the container image, as a concept with no implementation
**Input:** This project is the new Agentic-os Git workflow plugin. We are developing only a conceptual approach that functions as a git-workflow plugin within agentic-os.
**Raw input:** notes/raw-input.md
**Status:** draft

## Abstract

The edotz git-workflow plugin for agentic-os replaces the old cascade of GitHub Actions with a local workflow run through `app git <command>`: PRs are checked on GitHub and squash-merged to master, each release is one atomic local commit with its tag, and a GitHub App replaces the personal token.

### Background

The old single-repo and monorepo workflows rest on a chain of asynchronous Actions, backport PRs and the personal token of one developer; the plugin is the redesign that replaces them.

### Problem

The old approach causes many errors: up to five chained PRs and workflows per release, asynchronous backport PRs that conflict, no way to preview or fix a release locally, and every write right tied to the personal token of ohoeft.

### Constraints

- This is a conceptual approach only; nothing is implemented.
- The functionality ships inside agentic-os as a plugin, and the plugin neither chooses nor bundles an LLM provider.

### Goals

- Single repo and monorepo run start, commit, PR, promote, release (dry run and apply) and split through `app git <command>`.
- Each release is one atomic release commit with its tag, made locally.
- GitHub Actions only run the PR checks, and a GitHub App holds every write right.
- The changelog is linear.
- The process has no pitfalls, and the developer does not care how their changes are incorporated.

### Out of scope

- Any implementation.
- The design of the token service.
- The internals of generate-readme-action, the ide module and the vscode profiles.

### Audience

The edotz developers working in agentic-os sessions; one developer is in charge today.

### Approach

A local, deterministic workflow. PRs are squash-merged onto master after the GitHub checks. A promotion lands on the release branch named in RELEASE_BRANCH, where one atomic release commit with its tag is made locally and pushed by a GitHub App that is the only bypass actor. The monorepo split runs from the developer machine. How a promotion reaches the release branch is proposed (replay of the master commits onto it) and not confirmed.

### Measures

- Squash merge on master with a conventional PR title; linear history on master, 2.x and 1.x; no bypass on master.
- Rulesets with the GitHub App as sole bypass actor on 2.x and 1.x replace the classic branch protection.
- A token service gives the CLI short-lived installation tokens of the app.
- `release --dry-run` previews version and changelog with git-cliff; `release --apply` writes version, CHANGELOG and README into one release commit with its tag.
- The monorepo split runs locally with splitsh-lite and pushes the child repositories.
- Commit message and changelog summary come from `provider_run_prompt` on the host session; the container carries only git-cliff, splitsh-lite and gh.
- STAGE stays as a project-phase switch for the master ruleset, and the Stage Guard goes.
- All old CI except status-checks.yml is removed.
- Commands are `app git <command>`.
- The release branch is read from RELEASE_BRANCH.

### Why

The old chain breaks at any link and cannot be fixed locally; a local release can be previewed and corrected before GitHub sees it. A GitHub App with short-lived tokens removes the dependence on one person. Squash merge gives the linear changelog without history cleanup by the developer, and without release-please the reason for merge-commit-only history is gone.

### Alternatives

- Rebase merge on master: keeps every commit but makes the developer care about commit hygiene.
- Merge commits on master with git-cliff skipping them: the history stays non-linear.
- ohoeft as bypass actor, alone or with the app: dropped because the personal token is replaced completely.
- A key in the container or SSH for the split push: rejected for a token service, so no private key reaches a developer machine.
- Keeping release-please or the post-release README step: rejected with the rest of the old CI.
- Bundled claude or gemini CLIs, or a local Ollama: dropped because the provider belongs to agentic-os.
- LLM steps inside the container: not chosen.

### Risks

- A replay of master commits onto 2.x conflicts if a master commit touches files the release commit owns (proposed, not confirmed).
- branch-cleanup finds no merged branches after squash merges, so its detection is carried to the plan.
- The GitHub App, the token service and the local README generator have no design or code yet, and releases depend on them.

### Success

- A release can be previewed and corrected locally before anything reaches GitHub.
- No backport PR, no personal token and no cascade of workflows remain.
- The master changelog has one entry per merged PR, in order.

### Still open

- How a promotion reaches the release branch; replay is proposed and not confirmed.
- What the development phase of STAGE relaxes.
- How the README is generated locally in the release commit.
- The design of the token service.
- Pre-release flags and the tag format for monorepo packages.
- How workflow-status and branch-cleanup change after squash merge and replay.
- How the rulesets replace the classic branch protection code.

## Sources

- 260903-git-workflow.md: Role new, the primary draft: local CLI, splitsh-lite split, git-cliff changelog, rulesets, atomic release commit, container image; read in full. (verified)
- docs/git-workflow-monorepo/SKILL.md: Role old: the monorepo workflow with split action, childrepo release train and sync-to-monorepo backport, which the plugin replaces; read in full. (verified)
- docs/git-workflow-single/SKILL.md: Role old: the single-repo workflow with release-please, post-release backport and STAGE split, which the plugin replaces; read in full. (verified)
- docs/git-workflow: Role old: the old reference docs and slash command table (commands, lifecycle, preflight, workflow-env, generated-artifacts, callable-workflows, repo-details); all seven read. (verified)
- .github/workflows: Role old: the old CI, named in the input as .github/workflow; all 6 files read, the callables use the personal token NPM_AUTH_TOKEN. (verified)
- .claude/session/a24bcf21/260903_edotz_gitworkflow.pdf: Role context: the German analysis behind the draft, with the GitHub App migration, ruleset design and its open questions; read in full, 12 pages. (verified)
- /home/ohoeft/workspace/edotz.claude-code/bin/adapters/claude/agent.sh: Named in dialog (gap G4): the Claude adapter's adapter_run_prompt (claude -p, model haiku) and adapter_run_agent; read together with lib/provider.sh, whose provider_run_prompt dispatches to it. (verified)
- bin/modules, bin/lib, Dockerfile: Named in dialog (gap G3): the git module scripts, templates, hooks.yaml, github.sh, worktree.sh and the Dockerfile, read for what the plugin does today; the ide scripts were not read. (verified)

## Not looked at

- The detected scope ci has no declaration and so no memory.
- The path .github/workflow named in the input does not exist; .github/workflows was read in its place.
- The ide scripts, the commit-msg hook script and bin/config/env.defaults were not read.
- The 56 web references cited in the PDF were not followed.
- Whether agentic-os provides a way to run the framework inside the container was not looked at.

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
- Q12 By which mechanism does a promotion reach 2.x? (D9 names the criteria but not the mechanism; the developer answered only where the target branch comes from (D16).) -> no decision yet
- Q13 What stays of the old CI and the STAGE concept? (The draft keeps only status-checks.yml; the developer had not settled the Stage Guard and STAGE.) -> D17
- Q14 Where do the steps that need an LLM, the commit message and the changelog summary, run? (provider_run_prompt skips when the provider binary is missing, and the container entrypoint is app.) -> D18
- Q15 Which parts of the old CI does the plugin remove? (Four callables use the personal token and the release flow no longer needs release-please or backport PRs.) -> D19
- Q16 What is the purpose of this work, the problem it answers? (The abstract needs its background and problem.) -> D14
- Q17 What does the work have to reach, so that it can be told to be done? (The abstract needs its goals.) -> D15
- Q18 What does this concept not cover? (The abstract needs its constraints and what is out of scope.) -> D20
- Q19 Where does the target branch of a promotion come from? (The draft passes it as --target 2.x.) -> D16
- Q20 What does the development phase of STAGE relax on master? (D17 keeps STAGE as a switch without saying what it switches.) -> D21
- Q21 How is the README generated locally in the release commit? (generate-readme-action runs only as a GitHub Action today.) -> D22
- Q22 How is the token service designed? (D6 chooses a token service without a design.) -> D23
- Q23 Which pre-release flags and tag format does a release use, for a single repo and for monorepo packages? (The PDF names --pre=<channel> and packages/object/v2.1.0-beta.1.) -> D24
- Q24 How do workflow-status and branch-cleanup change after squash merge and replay? (Both rely on rev-list counts and git branch --merged.) -> D25
- Q25 How do the rulesets replace the classic branch protection code? (github.sh and workflow-setup only know the classic protection API.) -> D26

## Open

- Q12 By which mechanism does a promotion reach 2.x?

## Decisions

- D1 [decided] The concept name -> git-workflow-plugin (Taken from the goal: the new agentic-os git workflow plugin.; owner, 2026-10-20, concept-only)
- D2 [superseded] History policy of master and the release branches -> Split by branch: master takes PRs with merge commits only; 2.x and 1.x have linear history, promotion goes onto them and the atomic release commit sits on top, both by the bypass actor. (Keeps the individual conventional commits on master for git-cliff and gives the release branches the linear history of the draft. Its master half is superseded by D11.; owner, 2026-10-20, durable) superseded by D11
- D3 [decided] Command surface of the plugin -> app git <command>; the names gh-wf, gh wf and git-wf are dropped and the container entrypoint is app. (The framework app replaces bin/gh-wf and the plugin's git module already lives under app git.; owner, 2026-10-20, durable)
- D4 [decided] Replacement of the personal access token -> The current process, in which ohoeft's personal access token is used for runner authentication, monorepo splits, and creating pull requests, will be completely replaced by an internal GitHub App. (The developer's words, which the PDF repeats: a personal token binds the process to one person and one token lifetime.; owner, 2026-10-20, durable)
- D5 [decided] Bypass actor on 2.x and 1.x -> The GitHub App is the only bypass actor (actor_type Integration, mode always); master has no bypass for anyone. ohoeft as a user ID is dropped. (The personal token is replaced completely (D4); the PDF lists the app and ohoeft, the developer chose the app alone.; owner, 2026-10-20, durable)
- D6 [decided] How the CLI obtains the app token -> A token service issues short-lived installation tokens to the CLI, so the app's private key never reaches a developer machine. (The PDF names a GitHub App Token Service in its phase 1; the developer chose it. The service design is not specified.; owner, 2026-10-20, durable)
- D7 [decided] Goal for the changelog -> What I need is a linear changelog, adapt the rest to this goal. (The developer's words, given instead of an option; it is a requirement for the history and the release commit.; owner, 2026-10-20, durable)
- D8 [decided] Ease of development -> The development should be easy and the developer concern should not be the incorporation of his changes. (The developer's words, given instead of an option; the tool carries the incorporation, not the developer.; owner, 2026-10-20, durable)
- D9 [decided] Criteria for the promotion and release process -> I want a process with no pitfalls. If master tracks the new version, nice, if not, ok. The old approach causes a lot of errors and problems. I want to get rid of this. Today only one developer is in charge. (The developer's words, given instead of an option; master does not have to track the version, and the cascade of the old approach has to go.; owner, 2026-10-20, durable)
- D10 [decided] LLM provider for commit messages and the changelog summary -> The LLM provider mentioned in the raw concept is just an example; we are using agentic-os and ship the functionality within agentic-os as a plugin. The plugin neither chooses nor bundles an LLM CLI. (The developer's words; the provider side belongs to agentic-os. How a plugin makes a headless provider call was looked at afterwards: provider_run_prompt, see D18.; owner, 2026-10-20, durable)
- D11 [decided] Merge strategy of master -> Squash merge on master: one PR, one linear commit and one changelog entry taken from the PR title. master, 2.x and 1.x all have linear history, and the promotion and the atomic release commit go onto 2.x and 1.x by the bypass actor. (The developer chose it after the recommendation from D7 and D8. Without release-please the old reason for merge-commit-only history is gone; branch-cleanup's merged-branch detection has to change (D25).; owner, 2026-10-20, durable)
- D12 [proposed] Mechanism of the promotion to 2.x -> The CLI replays the new master commits onto 2.x; the release commit with version, CHANGELOG and README exists only on 2.x and its tag, and master's README carries no version, only releases/latest links and version badges. (Derived from D9: master need not track the version, and the local atomic release commit with its tag stays, unlike a release PR with a tag after an async merge. Unconfirmed: the developer answered with D16 instead of choosing. A replay conflicts if a master commit touches files the release commit owns, and workflow-status would have to compare patch IDs.; claude, 2026-10-20, durable)
- D13 [superseded] What stays of the old CI and the STAGE concept -> Not decided at the time: the draft keeps only status-checks.yml; the Stage Guard and the dev/prod STAGE split were open. (The developer said they were searching for the best fit and that a project start brings many changes. Answered by D17 for STAGE and D19 for the old CI.; owner, 2026-10-20, durable) superseded by D17
- D14 [decided] Purpose of the work -> A reliable release process: replace the cascade of GitHub Actions, the personal token and the asynchronous backport PRs with a local, deterministic workflow run through agentic-os that can be fixed before anything reaches GitHub. (The developer confirmed the recommendation drawn from D9 and the PDF analysis.; owner, 2026-10-20, durable)
- D15 [decided] Goal of the work -> Local release, GitHub only gates: single repo and monorepo run start, commit, PR, promote, release (dry run and apply) and split through app git <command>; each release is one atomic release commit with its tag; GitHub Actions only run the PR checks and the GitHub App holds every write right. (The developer confirmed the recommendation; it is done when no backport PR, no personal token and no cascade remain in the concept.; owner, 2026-10-20, durable)
- D16 [decided] Where the target branch of a promotion comes from -> The Release branch is determined via the env variable RELEASE_BRANCH. (The developer's words, given as the answer to the promotion mechanism; it drops the --target flag of the draft. How the promotion reaches the branch stays open (Q12).; owner, 2026-10-20, durable)
- D17 [decided] What stays of the STAGE concept and the Stage Guard -> STAGE stays as a project-phase switch for the master ruleset only: a lighter development phase and the full D5 rules in production. The Stage Guard goes. (The developer confirmed the recommendation, matching their note that a project start brings many changes. D5 removes the master bypass that STAGE used to toggle, and a promotion makes no PR to the release branch that the Stage Guard could block.; owner, 2026-10-20, durable)
- D18 [decided] Where the LLM steps run -> The commit message and the changelog summary come from provider_run_prompt on the host session, where the provider already runs; the container does only the deterministic tools (git-cliff, splitsh-lite, gh) and needs no provider binary and no LLM credentials. (The developer confirmed the recommendation. provider_run_prompt dispatches to the adapter of the active provider and skips when the binary is missing (bin/lib/provider.sh, adapters/claude/agent.sh).; owner, 2026-10-20, durable)
- D19 [decided] Which parts of the old CI the plugin removes -> All but the PR checks. Removed: the callables for release-please, post-release, merge-split-repo and sync-to-monorepo, the generated release and split callers, and release-please-config.json. Kept: status-checks.yml (commit-lint, biome, php-cs-fixer, shellcheck) as the only GitHub Action. (The developer confirmed the recommendation, as in the draft; all four removed callables use the personal token.; owner, 2026-10-20, durable)
- D20 [decided] What the concept does not cover -> Concept only, designs left out: any implementation, the design of the token service, the internals of generate-readme-action, the ide module and the vscode profiles are out of scope. The concept names what each of them must provide. (The developer confirmed the recommendation; it keeps the stated limit of a conceptual approach with no implementation.; owner, 2026-10-20, concept-only)
- D21 [decided] What the development phase of STAGE relaxes on master -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only)
- D22 [decided] How the README is generated locally in the release commit -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only)
- D23 [decided] How the token service is designed -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only)
- D24 [decided] Pre-release flags and tag format for a single repo and monorepo packages -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only)
- D25 [decided] How workflow-status and branch-cleanup change after squash merge and replay -> The plan settles it. (A detail that depends on the chosen approach and on Q12; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only)
- D26 [decided] How the rulesets replace the classic branch protection code -> The plan settles it. (A detail that depends on the chosen approach; the developer chose to carry the detail questions to the plan.; owner, 2026-10-20, concept-only)
