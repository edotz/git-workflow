## State
- PLAN-plugin (B-1) active: P1 to P3 done, P4 detailed as T4.1 to T4.13, none started. Roadmap: m1, m2, m3 done. Built and verified: token service, libs token, version, check, component, tool; release, promote; sandbox pilot (v0.1.0, v0.2.0).
- Linting runs through toolchain.linters of project.yaml (node with Biome 2.6.5, shell); the plugin lint module is gone. `app lint all full` passes; it exits 1 only on the stale lib-inventory snapshot (`app compile all`, not run).
- /aos:init re-run: .docker scope declared (its memory is active after /aos:config project-rules); architecture.md and identity.md updated. Removed and committed: workflow.env, its three templates, branch-protection.yaml, the four release callables.
- Everything of ours is committed and pushed (831a1b6). Not ours, untracked: .envrc, output-styles, 260903 draft, PDFs, PNGs, docs/git-workflow-*. The root .evolve.json provider block (trigger Dockerfile) matches no file: the developer deletes it.

## Open
1. START: T4.1 check, T4.2 start, T4.5 rules library (ready); then T4.3, T4.4, T4.6, T4.7, T4.10, T4.11; T4.8 inline; T4.9 hook-author; T4.12 pilot is the developer's.
2. T4.13 waits for the developer's check in the agentic-os project of notes/plugin-slash-commands.md (a plugin cannot ship a script command); amend through /aos:plan after the answer.
3. Amend the plan through /aos:plan: T3.9 to T3.11 describe the removed lint module; no task yet for the readers of workflow.env (worktree.sh:154-165, workflow-status.sh:17-19, workflow-setup.sh, which fails now) to take MAIN_BRANCH from .env.defaults and .env. Confirm D41 (the runner reads components.yaml itself).
4. Developer: do consumers still call _callable-status-checks.yml; keep or drop it; the status-checks.yml header still names workflow.env.
5. Code follow-ups from init: move the token-service base digest into the pins; one shebang `#!/usr/bin/env bash` for the ide scripts and templates; bin-lib.md memory is stale; the bin/lib declaration names two of seven libraries (the developer's).
6. T4.10/T4.11 Done checks are untested sketches; T3.11 closed without review; apply paths of release and promote ran only in the pilot.
7. Backlog: B-2 shared remote slug helper; none for plugin script commands. Developer: rotate the GH_TOKEN echoed twice; check .npmrc of edotz.nodejs-project; keep or retire the sandbox.

## Decided
- D42 to D44: T4.13 is one P4 task depending on T4.7; seven commands get a slash command; targets come from tiers registration-dir and hook-target.
- D33: .env.defaults is the fallback, the plugin-root .env overrides pins; one .docker/Dockerfile, root docker-compose.yaml. D34 to D41 stand.
- Developer, this session: workflow.env is a remnant, settings come from .env.defaults and .env; generated status-checks.yml stays the PR check; shellcheck clean means the local `lint domain full` run; agents, commands and skills scopes stay empty; ledger and resume are committed, root planning locks ignored.

## Traps
- No git stash. Port 8790. Never print a token or key. Commit header 100 characters at most.
- gh has no stored login: the exported GH_TOKEN is the developer login. The shell exports RELEASE_BRANCH=0.x, which beats .env: set it on the command line.
- SSH to GitHub fails now and then (publickey denied on a plain git push); gh credential helper over https works.
- `app lint node` is gone. A lint command without `full` runs staged and prints nothing when nothing is staged.
- Under purpose project the purpose cannot change; a new session needs --purpose deliverable. Tool output can arrive abbreviated: Read the file when exact text matters. version_next status 1 means no change: call it inside if.

## Read first
- plan ready, plan facts T4.1; notes plugin-slash-commands, pilot-release, token-service, component-declaration.
- Memory: MEMORY.md, project-linting-via-toolchain, project-sandbox-pilot-setup, feedback-orchestrator-authoring-and-review.
