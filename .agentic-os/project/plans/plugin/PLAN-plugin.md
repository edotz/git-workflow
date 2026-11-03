# PLAN-plugin
Generated from PLAN-plugin.json, do not edit.

**Goal:** Settle the foundations of the git-workflow plugin (the checked GitHub and tool behaviours, the token service and the component declaration) so that the tool image, release core, daily loop, monorepo and retirement phases can be detailed on checked ground.

## Abstract

### Summary

The plan opens the git-workflow plugin by closing what the milestone m1-foundations asks for: every verify claim of the white paper is checked against GitHub and the real tools, the token service interface, developer authentication, hosting and key custody are settled, and the component declaration is settled. Later phases for the tool image, release core, daily loop, monorepo and retirement are outlined only, one per later milestone of the roadmap.

### Outcome

Five notes in the concept's notes directory, one of them recording the sandbox: one with a row per marked line of the white paper for the GitHub App behaviours, one for the tool and ecosystem claims, one for the token service contract with authentication, fallback and hosting, and one for the component declaration with its path resolution and pre-release handling. The milestone gate of m1-foundations can then be read off these notes.

### Phases

- P1 Foundations: checked claims, token service, component declaration: 5 tasks
- P2 Tool image: 0 tasks
- P3 Release core: 0 tasks
- P4 Daily loop and guards: 0 tasks
- P5 Monorepo: 0 tasks
- P6 Retire the old approach: 0 tasks

### Cost

Five tasks in the detailed phase, one note each: the developer's sandbox registration and four research and settling notes. The five outlined phases cost nothing until they are detailed in an amend.

### Decisions to confirm

none

### Open points

none

### Risks

Several GitHub behaviours the release rests on are unverified and may be refuted, which would change decided concept decisions (the App as the only bypass actor, the GitHub Release created by the App, --latest=false). T1.1 needs a test GitHub App and a sandbox repository that the developer registers first. The token service has no design yet and every remote write depends on it. The white paper marks 18 lines against the concept's 13 claims; the plan covers all 18 and does not reconcile the concept's count.

### Success

Each marked line of the white paper has a row with a result and evidence, each refuted claim names the decision it puts in doubt, and the developer can read the token service contract and the component declaration as settled. The milestone m1-foundations gate can then be called met.

**Track:** deliberative  **Items:** B-1
**Status:** active  **Mode:** inline

## P1 Foundations: checked claims, token service, component declaration (detailed)

| Title | Task | Owner | Depends | Status |
|---|---|---|---|---|
| Register the test GitHub App and sandbox repository | T1.0 | developer | - | done |
| Check the GitHub App behaviours the release depends on in a sandbox repository | T1.1 | developer | T1.0 | done |
| Check the tool and ecosystem claims of the white paper against current documentation and the real tools | T1.2 | inline | - | pending |
| Settle the token service contract, developer authentication, fallback and hosting | T1.3 | inline | T1.1 | pending |
| Settle the component declaration, its path resolution and pre-release handling | T1.4 | inline | T1.2 | pending |

**Register the test GitHub App and sandbox repository** (T1.0)
- Why: The checks of the App behaviours cannot run without an App and a repository that the project does not yet hold; plan decision D3 puts this before the first check, so a task enforces the order.
- Result: A note that names the test App, the sandbox repository and the settings the checks run under.
- Done: The note exists with the three sections, and the Settings section names the ruleset level and the plan tier.
- Fails: T1.1 would start without an App or a repository, or run against settings that differ from the consuming projects without saying so.

**Check the GitHub App behaviours the release depends on in a sandbox repository** (T1.1)
- Why: The release design depends on GitHub behaviours that nobody has checked; the concept names them as the first thing the plan verifies. This task has the most unknowns, so it comes first and a refuted claim shows before anything is built on it.
- Result: A report with one row per marked line, each with a result and the evidence behind it.
- Done: The report file exists and holds a row for each of the eleven lines; each row ends in confirmed, refuted or changed, names how it was run, and a refuted or changed row names the concept decision it puts in doubt.
- Fails: The release commit, the tag, the GitHub Release by the App and the single required check would be built on unchecked behaviour and could fail only when the first project releases.
- Carries: What the development phase of STAGE relaxes on master (CONCEPT-git-workflow-plugin:D29); Who may make the release commit, the tag and the promote (CONCEPT-git-workflow-plugin:D30); How the GitHub Release is created (CONCEPT-git-workflow-plugin:D40); How one latest release per repository works with several components (CONCEPT-git-workflow-plugin:D56)

**Check the tool and ecosystem claims of the white paper against current documentation and the real tools** (T1.2)
- Why: The image base, the version-file writers and the pre-release handling cannot be decided on claims nobody checked; these claims need no GitHub account, so they run independently of the GitHub checks.
- Result: A report with one row per marked line, each with a result, the version checked and the evidence.
- Done: The report file exists and holds a row for each of the seven lines, each with a result of confirmed, refuted or changed and a named method.
- Fails: The image could get a base the splitsh-lite binary does not run on, and the version writers and the pre-release rule would be built on a guess.
- Carries: What the container does (CONCEPT-git-workflow-plugin:D34); The versioning unit and the tag format (CONCEPT-git-workflow-plugin:D38); Where the plugin ends (CONCEPT-git-workflow-plugin:D39); How pre-releases are handled (CONCEPT-git-workflow-plugin:D47); Which writers align the version files (CONCEPT-git-workflow-plugin:D50); How the modules call the tool image (CONCEPT-git-workflow-plugin:D55)

**Settle the token service contract, developer authentication, fallback and hosting** (T1.3)
- Why: Every remote write (release, promote, split, rules-sync) needs a token from the service; without a settled contract the library that fetches the token cannot be planned.
- Result: A note that states the contract between the CLI and the token service, how a developer is authenticated, what happens when the service is unavailable, and where the service runs.
- Done: The note exists with the four sections, cites the App permissions of row L500, and each section states a decided answer and not an open choice.
- Fails: The GitHub library cannot be designed, and the first release would stall on the question of where its token comes from.
- Carries: Replacement of the personal access token (CONCEPT-git-workflow-plugin:D4); How the CLI obtains the app token (CONCEPT-git-workflow-plugin:D6); How the token service is designed (CONCEPT-git-workflow-plugin:D23); How the token service authenticates a developer (CONCEPT-git-workflow-plugin:D48)

**Settle the component declaration, its path resolution and pre-release handling** (T1.4)
- Why: The release, the split and the aggregate check all read the component declaration; they cannot design their data interfaces until its format is fixed. The roadmap gate of this milestone names it.
- Result: A note that fixes the declaration's fields, how a component's paths are resolved, how a pre-release is handled and how a single repository is declared.
- Done: The note exists with the four sections, cites row L390 for the pre-release rule, and each section states a decided answer.
- Fails: The release, split and check modules would each guess the declaration's shape, and the old PACKAGES_DIR and per-package env files would stay.
- Carries: The versioning unit and the tag format (CONCEPT-git-workflow-plugin:D38); The format of the component declaration (CONCEPT-git-workflow-plugin:D44); Whether JS components take their paths from the workspace graph (CONCEPT-git-workflow-plugin:D46); How pre-releases are handled (CONCEPT-git-workflow-plugin:D47)

Gate: (f=.agentic-os/project/concepts/git-workflow-plugin/notes/sandbox.md; test -s $f && grep -q '^## Repository' $f && grep -q '^## App' $f && grep -q '^## Settings' $f) && (f=.agentic-os/project/concepts/git-workflow-plugin/notes/verify-github.md; for l in 261 316 411 441 467 470 491 500 520 523 654; do grep -qE "^[|] L${l} [|][^|]*[|][^|]*[|][[:space:]]*(confirmed|refuted|changed)[[:space:]]*[|][^|]*[^|[:space:]][^|]*[|][[:space:]]*\$" $f || exit 1; done; [ "$(grep -E '^[|] L[0-9]+ [|][^|]*[|][^|]*[|][[:space:]]*(refuted|changed)[[:space:]]*[|]' $f | grep -cvE 'D[0-9]+')" = 0 ]) && (f=.agentic-os/project/concepts/git-workflow-plugin/notes/verify-tools.md; for l in 237 239 390 460 595 624 786; do grep -qE "^[|] L${l} [|][^|]*[|][^|]*[|][[:space:]]*(confirmed|refuted|changed)[[:space:]]*[|][^|]*[^|[:space:]][^|]*[|][[:space:]]*\$" $f || exit 1; done) && (f=.agentic-os/project/concepts/git-workflow-plugin/notes/token-service.md; test -s $f && grep -q '^## Client contract' $f && grep -q '^## Authentication' $f && grep -q '^## Fallback' $f && grep -q '^## Service hosting' $f && grep -q 'L500' $f && ! grep -qiE 'TBD|TODO|open question' $f) && (f=.agentic-os/project/concepts/git-workflow-plugin/notes/component-declaration.md; test -s $f && grep -q '^## Fields' $f && grep -q '^## Path resolution' $f && grep -q '^## Pre-releases' $f && grep -q '^## Single repository' $f && grep -q 'L390' $f && ! grep -qiE 'TBD|TODO|open question' $f)

## P2 Tool image (outlined)

Define the pinned image with docker compose and a .docker directory, choose docker exec or an ephemeral container per call, and give the modules one library function that builds every tool call (roadmap milestone m2-tool-image).

## P3 Release core (outlined)

Build release --dry-run and --apply with the minimum check, the version-file writers, the local README generation, the GitHub Release by the App and promote to the release tag (roadmap milestone m3-release-core).

## P4 Daily loop and guards (outlined)

Build start, commit and pr, the aggregate status check, rules-sync with the STAGE switch, the pre-push guard and the adapted workflow-status and branch-cleanup (roadmap milestone m4-daily-loop).

## P5 Monorepo (outlined)

Release each component on its own, split components marked split: yes with splitsh-lite, baseline the existing child repositories and apply --latest=false in multi-component repositories (roadmap milestone m5-monorepo).

## P6 Retire the old approach (outlined)

Remove the old CI except status-checks.yml, replace the classic protection code, and correct the stale project context wording (roadmap milestone m6-retire-old).

## Review focus

- T1.1: The done check counts report rows; it does not test that a row marked confirmed rests on a run against the sandbox. A claim about the behaviour of an App token must not be confirmed from documentation alone.
- T1.1: The sandbox repository may use settings (repository ruleset against organisation ruleset, plan tier) that differ from the consuming projects, so a confirmed row can fail in production. Each row should name the settings it was run under.
- T1.2: The done check counts rows only. The splitsh-lite linkage and libgit2 rows must be checked against the release binary version the image will pin, not against whichever version is newest.
- T1.3: The note must stay a contract and a decision record. Server code or deployment scripts of the token service would exceed what the concept settled, and no done check catches that.
- T1.4: The declaration must hold a single source for a component's paths (the workspace graph or an explicit list per component), and its single-repository case (one component at the root) must be written out. No done check reads the note for either.

## Review reports

- order: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin/plan-review-order.md
- registrations: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin/plan-review-registrations.md
- assumed-code: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin/plan-review-assumed-code.md
- precedent: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin/plan-review-precedent.md
- proofs: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin/plan-review-proofs.md

## Decisions

- D1 [decided] Which phases the plan details -> P1 is detailed; P2 to P6 are outlined, one per later milestone of the roadmap (P2 to P6 depend on the checks of P1. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D2 [decided] Where the check reports and design notes are written -> .agentic-os/project/concepts/git-workflow-plugin/notes/ (It lies inside the project scope trigger and next to the concept's raw input. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D3 [decided] How the GitHub App behaviours are checked -> A test GitHub App installed on a sandbox repository that the developer registers before T1.1 starts (The behaviours cannot be checked by reading documentation alone. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D4 [decided] How the token service authenticates a developer (CONCEPT-git-workflow-plugin D48, left to the plan) -> An existing gh login checked against organisation membership (The white paper's recommendation in row Q-G; it needs no new credential on a developer machine. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D5 [decided] What happens when the token service is down -> Fail closed: no App write happens while the service is down (Concept decision D30 leaves no human write path, and a manual token would reopen the personal-token problem. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D6 [decided] Format of the component declaration (CONCEPT-git-workflow-plugin D44, left to the plan) -> One structured file at the repository root with explicit lists for checks and version files, and no kind field (The white paper's recommendation in row Q-O. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D7 [decided] Whether JS components take their paths from the workspace graph (CONCEPT-git-workflow-plugin D46) -> Yes: the workspace graph and turbo --affected; other components list paths in the declaration (The white paper's recommendation in row Q-R. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D8 [decided] How pre-releases are handled (CONCEPT-git-workflow-plugin D47) -> Settled after T1.2 reports white paper line 390 (the git-cliff pre-release counter); T1.4 writes the answer into its note (The white paper's row Q-H says verify first, and T1.4 depends on T1.2. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D9 [decided] How the plan's tasks are carried out -> inline (No task is bash or hook code, T1.1 needs the developer's own account, and T1.3 and T1.4 are dialogue. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D10 [decided] Whether T1.3 also settles where the token service runs and who holds the App key -> Yes: the token service note gets a Service hosting section naming the hosting and the key custody (The m1 gate says the token service is settled, and concept D6 says the App private key never reaches a developer machine. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D11 [decided] Which task owns the white paper lines 411 and 654 -> T1.1 takes both lines; its report holds eleven rows (Both are GitHub latest-release behaviour under concept decision D56; the white paper marks 18 lines and no task owned these two. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D12 [decided] How the verify runs prove the notes -> The verify runs test content: the result column of each row, a named decision on refuted or changed rows of T1.1, the citation of L500 in the token service note and of L390 in the component declaration note, and no TBD, TODO or open question (A structure-only check passed empty or TBD notes. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D13 [decided] How the sandbox prerequisite of plan decision D3 is enforced -> A developer-owned task T1.0 writes sandbox.md; T1.1 depends on it (No task or dependency encoded the order. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D14 [decided] What the P1 gate proves -> The gate runs the verify.run of every P1 task (T1.0 to T1.4), each in its own subshell, joined with && (A test -s over the notes passed one-row notes and could not see a missing line or the sandbox note; the milestone gate m1-foundations needs the coverage and content proofs. Developer answer, recommended option.; developer, 2026-11-03, plan-only)

## Revisions

- 2026-11-03 Cover white paper lines 411 and 654 in T1.1, make the verify runs test content, add the developer task T1.0 for the sandbox and record D11 to D13 (affects T1.0, T1.1, T1.2, T1.3, T1.4, D11, D12, D13) -- Review findings of the lenses proofs, order and assumed-code, settled with the developer in round 1 (claude)
- 2026-11-03 Replace the grep -vq test in the T1.1 verify run by a grep -c test, which gives the same result on every grep (affects T1.1, D12) -- The first form returned the wrong exit code under the grep wrapper of this shell, so a refuted row without a named decision would have passed; D12 is unchanged (claude)
- 2026-11-03 The P1 gate chains the verify runs of T1.0 to T1.4 instead of testing four files for size, and decision D14 records it (affects P1, D14) -- Review finding of the lens proofs: the gate could not see the coverage gap or the missing sandbox note, settled with the developer in round 2 (claude)
