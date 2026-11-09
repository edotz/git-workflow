## State
- PLAN-plugin (B-1) active: P1 to P3 done, P4 detailed as T4.1 to T4.14, none started. Roadmap: m1, m2, m3 done. Built and verified: token service, libs token, version, check, component, tool; release, promote; sandbox pilot (v0.1.0, v0.2.0).
- Linting runs through toolchain.linters of project.yaml (node with Biome 2.6.5, shell); the plugin lint module is gone (D45). `app compile all` ran; `app lint all full` passes (json, node, shell).
- T4.14 (new) moves the branch settings to GIT_WORKFLOW_MAIN_BRANCH and GIT_WORKFLOW_RELEASE_BRANCH of the project .env files (D46), cuts workflow-setup to them (D47); T4.1, T4.2, T4.10 and T4.11 wait for it (D48).
- Removed and committed: workflow.env, its templates, branch-protection.yaml, the release callables, _callable-status-checks.yml, the old docs/git-workflow reference docs (developer). Root .evolve.json scope_trigger is docker-compose.yaml. The ide scripts and templates use `#!/usr/bin/env bash`.
- Not ours: .envrc, .claude/output-styles, and the hooks.json entry pre-commit/scope-checks added by the compile.

## Open
1. START: T4.14 first; then T4.1 check, T4.5 rules library, T4.2 start; then T4.3, T4.4, T4.6, T4.7, T4.10, T4.11; T4.8 inline; T4.9 hook-author; T4.12 pilot is the developer's.
2. T4.13 waits for the developer's check in the agentic-os project of notes/plugin-slash-commands.md (a plugin cannot ship a script command); amend through /aos:plan after the answer.
3. The status-checks.yml header still names workflow.env; T4.8 replaces the file. P6 is outlined: the classic protection code and bin/modules/git/templates (branch-protection.sh, workflow-callers.sh, release-please.sh) go there.
4. Code follow-ups: move the token-service base digest into the pins; seven bin/lib scripts still use `#!/bin/bash`; the bin/lib declaration names two of seven libraries (the developer's).
5. T4.10/T4.11 Done checks are untested sketches; T3.11 closed without review; apply paths of release and promote ran only in the pilot.
6. Backlog: B-2 shared remote slug helper; none for plugin script commands. Developer: rotate the GH_TOKEN echoed twice; check .npmrc of edotz.nodejs-project; keep or retire the sandbox.

## Decided
- D42 to D44: T4.13 is one P4 task depending on T4.7; seven commands get a slash command; targets come from tiers registration-dir and hook-target.
- D45 to D48: toolchain linters replace the lint module; GIT_WORKFLOW_ branch keys from the project .env files; workflow-setup cut to them; T4.1 waits for T4.14.
- D33: .env.defaults is the fallback, the plugin-root .env overrides pins; one .docker/Dockerfile, root docker-compose.yaml. D34 to D41 stand; D41 runner detail confirmed 2026-11-09.
- Developer: generated status-checks.yml stays the PR check; agents, commands and skills scopes stay empty; ledger and resume are committed, root planning locks ignored.

## Traps
- No git stash. Port 8790. Never print a token or key. Commit header 100 characters at most.
- `app plan amend --dry-run` writes the plan: never use it to test; test the jq program with jq on the plan file.
- gh has no stored login: the exported GH_TOKEN is the developer login. The shell exports RELEASE_BRANCH=0.x, which beats .env until T4.14 renames the key: set it on the command line.
- SSH to GitHub fails now and then (publickey denied on a plain git push); gh credential helper over https works.
- A lint command without `full` runs staged and prints nothing when nothing is staged.
- Under purpose project the purpose cannot change; a new session needs --purpose deliverable. Tool output can arrive abbreviated: Read the file when exact text matters. version_next status 1 means no change: call it inside if.

## Read first
- plan ready, plan facts T4.14; notes plugin-slash-commands, pilot-release, token-service, component-declaration.
- Memory: MEMORY.md, project-linting-via-toolchain, project-sandbox-pilot-setup, feedback-orchestrator-authoring-and-review.
