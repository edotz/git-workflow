## State
- PLAN-plugin (B-1) active: P1 to P3 done; P4 detailed as T4.1 to T4.19, only T4.14 done (closed by hand: no docker here). The plan was reviewed on 2026-11-09 with five lenses (reports plan-review-*.md under the session reports) and the findings settled as D54 to D57. `plan check`, `app lint all full` and `app compile all` pass.
- Branch chore/git-workflow-concept is pushed up to c3f182f; the tree is clean except the untracked .claude/output-styles.
- Settings live in the project-root .env, the only env file the framework loads: GIT_WORKFLOW_MAIN_BRANCH=master and GIT_WORKFLOW_RELEASE_BRANCH=0.x are set; GIT_WORKFLOW_STAGE, GIT_WORKFLOW_WORKTREE_DIR (default $HOME/worktrees) and GIT_WORKFLOW_APP_ID come with T4.5, T4.15 and T4.6.
- The leaked classic token is revoked; gh has a stored login (ohoeft); .envrc is ignored.

## Open
1. START: author group 1 with /aos:bash-authoring under the bash-framework and bash-utility rules: T4.15 (worktree dir), T4.18 (remote library), T4.1 (check), T4.5 (rules library). Then T4.2; T4.3, T4.4, T4.6; T4.7; T4.10, T4.11; T4.8 inline; T4.9; T4.16, T4.13, T4.17, T4.19; T4.12 is the developer's pilot.
2. Concept git-workflow-plugin: record the dependency on B-62 and continue /aos:concept (Q12 open).
3. Context files at commit time, no task: bin-lib.md and bin/lib/.evolve.json after T4.5, T4.15 and T4.18; bin-modules.md after T4.7.
4. T4.8 replaces status-checks.yml, whose header names workflow.env; P6 is outlined (classic protection code, bin/modules/git/templates).
5. Untested sketches: the new verifies of T4.6 and T4.9 to T4.12; the docker tests need docker. B-2 holds the old slug copies; the token-service digest should move into the pins. Developer: check .npmrc of edotz.nodejs-project; keep or retire the sandbox.

## Decided
- D49, D50: the branch settings come from the project-root .env only (GIT_WORKFLOW_ keys, master in code) and workflow-setup is reduced to validate, because the framework loads no project .env.defaults.
- D51, D52: GIT_WORKFLOW_STAGE; the worktree dir is a setting and T4.15 comes before T4.2.
- D53: the slash commands are script commands, commands/git/<name>.sh forwarding to app git <name> (B-62 is done), in three tasks T4.16, T4.13, T4.17.
- D55, D56, D57: the App id is GIT_WORKFLOW_APP_ID; T4.18 holds the remote library and release and promote wait for B-2; T4.19 enables the pre-push hook and T4.17 lists commands.json.

## Traps
- No git stash. Never print a token. Commit header 100 characters at most. A failed commit leaves its files staged.
- `app plan amend --dry-run` writes the plan: test the jq program offline on a merged copy.
- A temp repo of a verify or test needs an empty .agentic-os directory, or the bootstrap exits 3.
- This tool shell skips .env (inherited bootstrap): check settings with `env -i HOME="$HOME" PATH="$PATH" bash ${BU_ROOT}/app git workflow-setup`. A shell with the old GH_TOKEN export fails: use a new one. SSH to GitHub fails now and then; https with the gh credential helper works.
- Tool output can arrive abbreviated: Read the file when exact text matters.

## Read first
- plan facts for T4.15, T4.18, T4.1, T4.5; the resume note; the review reports.
- Memory: MEMORY.md, feedback-plan-amend-dry-run, project-sandbox-pilot-setup, feedback-orchestrator-authoring-and-review.
