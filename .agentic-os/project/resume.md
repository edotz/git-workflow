## State
- PLAN-plugin (B-1) active: P1 to P3 done, P4 detailed as T4.1 to T4.19, only T4.14 done (closed by hand: its Done command needed docker and an .agentic-os temp dir). Roadmap: m1, m2, m3 done. Built and verified: token service, libs token, version, check, component, tool; release, promote; sandbox pilot (v0.1.0, v0.2.0).
- Plan review ran on 2026-11-09 with five lenses (reports under .claude/session/a24bcf21/reports/PLAN-plugin/plan-review-*.md) and two rounds settled the findings: D54 to D57. `plan check` and `app lint all full` pass; `app compile all` ran.
- Slash commands (B-62 of the framework is done, a script command takes its script from the tier chain): T4.13 was split by D53 into T4.16 (seven scripts commands/git/<name>.sh, bash-author), T4.13 (commands/commands.yaml, dynamic-author) and T4.17 (plugin.yaml provides commands, compile, commands.json). The compile adds the commands to .agentic-os/commands/commands.json by bare name; no collision with the framework names today.
- Settings in the project-root .env, which the framework loads (the process environment wins; a project .env.defaults is never loaded): GIT_WORKFLOW_MAIN_BRANCH=master and GIT_WORKFLOW_RELEASE_BRANCH=0.x (set, D49; 1.x is the old diverged cascade branch), GIT_WORKFLOW_STAGE (D51, T4.5/T4.6), GIT_WORKFLOW_WORKTREE_DIR default $HOME/worktrees (D52, T4.15), GIT_WORKFLOW_APP_ID (D55, T4.6). Check loaded values with `env -i HOME="$HOME" PATH="$PATH" bash ${BU_ROOT}/app git workflow-setup`: the tool shell inherits a bootstrap and skips .env.
- gh: the old classic token was revoked; the developer stored a login with gh auth login (account ohoeft, scopes repo, workflow, read:org). A shell that still exports the old GH_TOKEN fails; start a new shell. .envrc is ignored.
- Not ours: .claude/output-styles (untracked). TODO.md was deleted by the developer.

## Open
1. START the authoring (aos:bash-authoring, one group at a time, bash-framework and bash-utility rules): group 1 T4.15 (worktree dir), T4.18 (remote library), T4.1 (check), T4.5 (rules library); then T4.2 (after T4.15), T4.3, T4.4, T4.6 (after T4.18 and T4.5), T4.8 inline, T4.9 hook-author (after T4.7), T4.10, T4.11, T4.7 registration, T4.16, T4.13, T4.17, T4.19; T4.12 pilot is the developer's.
2. Concept git-workflow-plugin: record the dependency on B-62 and continue /aos:concept git-workflow-plugin (Q12 is open); notes/plugin-slash-commands.md is answered.
3. Context files to keep at commit time (no task): bin/lib/.evolve.json and bin-lib.md after T4.5, T4.15 and T4.18 (worktree path, libraries list), bin-modules.md after T4.7 (command count).
4. The status-checks.yml header still names workflow.env; T4.8 replaces the file. P6 is outlined: the classic protection code and bin/modules/git/templates go there.
5. Code follow-up: move the token-service base digest into the pins; the old remote-slug and identity copies in release.sh and promote.sh wait for B-2.
6. Seven weaker proofs (T4.1, T4.3, T4.4, T4.5, T4.8, T4.15, and T4.16/T4.17) and the strengthened verifies of T4.6, T4.9, T4.10, T4.11 and T4.12 are untested sketches; T3.11 closed without review; apply paths of release and promote ran only in the pilot.
7. Developer: check .npmrc of edotz.nodejs-project; keep or retire the sandbox; run the docker tests where docker works.

## Decided
- D42 superseded by D53; D43 and D44 stand. D45 to D52: toolchain linters replace the lint module; D46/D47 superseded by D49/D50; T4.1 waits for T4.14; D51 STAGE as GIT_WORKFLOW_STAGE; D52 worktree dir setting and T4.15.
- D53 slash commands as script commands in three tasks; D54 verify repairs (mkdir .agentic-os in temp repos) and five stronger proofs; D55 App id; D56 remote library T4.18 without the refactor; D57 registry coverage (T4.19, commands.json in T4.17).
- D33: .env.defaults is the fallback, the plugin-root .env overrides pins. D34 to D41 stand.
- Developer: generated status-checks.yml stays the PR check; agents, commands and skills scopes stay empty; ledger and resume are committed.

## Traps
- No git stash. Port 8790. Never print a token or key. Commit header 100 characters at most. A failed commit leaves its files staged: check `git diff --cached` before the next one.
- A test or verify that runs a script in a throwaway repository needs an empty .agentic-os directory there, or the bootstrap dies with exit 3.
- `app plan amend --dry-run` writes the plan: test the jq program with jq on a merged copy of the plan file, never with --dry-run.
- SSH to GitHub fails now and then (publickey denied on a plain git push); gh over https with the credential helper works.
- A lint command without `full` runs staged and prints nothing when nothing is staged.
- Tool output can arrive abbreviated: Read the file when exact text matters.

## Read first
- plan ready, plan facts T4.15 T4.18 T4.1 T4.5; the review reports and notes plugin-slash-commands, pilot-release, token-service, component-declaration.
- Memory: MEMORY.md, project-linting-via-toolchain, project-sandbox-pilot-setup, feedback-orchestrator-authoring-and-review.
