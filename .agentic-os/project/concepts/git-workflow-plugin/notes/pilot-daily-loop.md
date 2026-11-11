# Pilot daily loop in the sandbox for PLAN-plugin T4.12

The daily loop run on 2026-11-10 against the pilot single repository of `pilot-release.md`: `rules-sync` at both stages, a change made with the start, commit and pr commands, the aggregate check, the squash merge, a direct push at the development stage and the pre-push guard. It holds no secret: the App key stayed on the developer machine and no token was written to a file or into this note.

## Repository

- Repository: `edotz/git-workflow-sandbox`, private, working copy `/home/ohoeft/worktrees/git-workflow-sandbox`, branch `master` at `0611b67` before the run; merge settings squash only.
- Sandbox `.env`: `GIT_WORKFLOW_MAIN_BRANCH=master`, `GIT_WORKFLOW_RELEASE_BRANCH=0.x`, `GIT_WORKFLOW_STAGE=production`, `GIT_WORKFLOW_APP_ID=5593711`. The shell that ran the commands exported `PROJECT_ROOT` of the plugin repository, `GIT_WORKFLOW_RELEASE_BRANCH=0.x` and `GIT_WORKFLOW_STAGE=development`; the commands ran with `PROJECT_ROOT` set to the clone and the four settings passed on the command line.
- Token service: the container of `docker-compose.yaml` on `127.0.0.1:8790` with the key of the sandbox App mounted read-only; it exited when docker restarted and was started again.
- Before the run the repository held the ruleset `master-protection` of the T1.1 checks, on the default branch, with the App as bypass actor.
- The slash commands dispatch to `bash ${BU_ROOT}/app git <name> $ARGUMENTS` (D59); the run called `app git start`, `commit` and `pr` itself, so the slash-command layer (the compiled files under `.claude/commands/git/`) was not driven by the harness.

## Result

- rules-sync, production: the dry run listed `master` and `release` as create and `legacy` as skipped (`GIT_WORKFLOW_LEGACY_BRANCHES` unset, D58). The apply created the rulesets `master` (`refs/heads/master`: `pull_request`, `required_status_checks`, `required_linear_history`, the App as bypass actor) and `release`; the repeated apply reports `update` for both, not unchanged. The first apply ran with `RELEASE_BRANCH` from the shell and put `release` on `0.x`; a second run with a branch name `release` moved it to `refs/heads/release`; the last apply restored `0.x`.
- /git:start: `app git start feat pilot-daily-loop` created the branch `feat/pilot-daily-loop` and its worktree from `master` and printed the path. With the default base the worktree lands inside the clone (`~/worktrees/git-workflow-sandbox/feat-pilot-daily-loop`), where `commit` failed with "plugin registry not built": the relative plugin path of the sandbox `project.yaml` (`../../workspace/edotz.git-workflow`) resolves two levels below `$HOME` only. With `GIT_WORKFLOW_WORKTREE_DIR=$HOME` the worktree is `~/git-workflow-sandbox/feat-pilot-daily-loop` and the path resolves.
- /git:commit: `app git commit pilot.txt --message "feat(sandbox): add a pilot note" --yes` made the commit `fa19081` with the conventional message.
- /git:pr: the dry run printed branch, title and the commit list; the apply pushed the branch and opened pull request #8.
- Aggregate check: `check` was queued and the merge state `BLOCKED`; after the job passed (5 seconds) the state was `CLEAN`. The context `check` is required by `bin/config/rulesets.yaml`. The old `master-protection` required it as well, so the block cannot be told apart from the new ruleset in this run.
- Squash merge: the developer merged #8 (the classifier declined `gh pr merge` from the session). `master` holds `14260ce` `feat(sandbox): add a pilot note (#8)` with the single parent `0611b67`. Merge commit and rebase are off in the repository.
- rules-sync, development: the apply left the ruleset `master` without rules and `release` protected on `0.x`.
- Direct push: the first push of `0a13fcf` to `master` was rejected with "push declined due to repository rule violations". The cause was `master-protection`, not rules-sync: the rules in force on `master` were its `deletion`, `non_fast_forward`, `pull_request` and `required_status_checks`, and only the App bypasses it. `rules-sync` manages its own rulesets by name and leaves others alone. After the developer deleted `master-protection` the push was accepted (`0a13fcf` on `origin/master`), and no rule applies to `master`.
- Hooks and pre-push guard: `app git shims` installed `pre-commit`, `commit-msg` and `pre-push` into `.git/hooks` and replaced the stale template hooks that called `agentic-os`. The shim alone did nothing: `app hooks install` registered the plugin hook `pre-push/minimum-check` as disabled although its header says `default=on`, and the shim only warned "No hook registry ... no hooks run". After `app hooks enable pre-push minimum-check` a real `git push` of a branch with the commit `red commit without a type` was stopped by the guard: "commit lint failed", "minimum check of 'sandbox' failed", exit 1, and the remote got no new branch. The green direct push above passed the same guard.
- Docker tests: `tests/git-promote/ff.sh` and `tests/git-release/dry-run.sh` pass, with exit 0 for both.

## Defects the pilot found

- A repository with an older ruleset keeps its rules: rules-sync neither lists nor retires rulesets it did not create, so a push at the development stage is still declined. A consuming project has to remove them (P6 retires the classic protection code).
- A repeated `rules-sync --apply` reports `update` for rulesets that did not change; the release branch name in the process environment wins over the project `.env`, as in `pilot-release.md`.
- `app hooks install` registers plugin hooks disabled even when the script header says `default=on`; the guard stays off until the developer enables it. It also writes `.agentic-os/hooks/`, `.agentic-os/hooks.map.claude.json` and `.claude/` into the project.
- The relative plugin path in the sandbox `project.yaml` breaks for a worktree that is not two levels below `$HOME`.
