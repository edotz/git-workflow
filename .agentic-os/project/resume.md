## State
- PLAN-plugin (B-1) active, P4: T4.1 to T4.11, T4.13 to T4.15, T4.18, T4.19 done; T4.16 dropped (D59); T4.17 pending; T4.12 is the developer's pilot. All findings settled but T4.13 finding 2 (argument-hint). Shellcheck runs from node_modules through the lint; docker is installed here.
- Branch chore/git-workflow-concept is pushed up to 81f10f2. Uncommitted, not from the plan: adapters/git/hooks/hooks.yaml (rewritten by compile hooks, "the plugin owns it") and untracked .git-templates/hooks/ (pre-push, pre-commit, commit-msg shims); plus .claude/output-styles. The developer decides on the first two.
- .env sets GIT_WORKFLOW_MAIN_BRANCH=master and GIT_WORKFLOW_RELEASE_BRANCH=0.x; GIT_WORKFLOW_STAGE, GIT_WORKFLOW_WORKTREE_DIR, GIT_WORKFLOW_APP_ID and GIT_WORKFLOW_LEGACY_BRANCHES are not set (the App id is needed for rules-sync --apply, the legacy setting for the legacy ruleset).

## Open
1. START: T4.17 (inline): add commands to provides in plugin.yaml, run app compile commands, check .claude/commands/git/*.md for the seven commands, the argument-hint and disable-model-invocation on pr, release, promote and rules-sync, and write .agentic-os/commands/commands.claude.yaml (D60); then settle T4.13 finding 2.
2. Decide what to do with the generated hooks.yaml change and .git-templates/ (the pre-push guard fires only through those shims).
3. T4.12 pilot (developer): the Done check names no second rules-sync apply (only a real apply shows GitHub default fields breaking unchanged); run a real git push through the shim; re-run tests/git-promote/ff.sh and tests/git-release/dry-run.sh, closed by hand in T4.14 when docker was thought missing.
4. Context: .evolve.json of .github/workflows names github-workflows.md, which does not exist; the purpose in bin/modules/.evolve.json is stale.
5. Framework owner: git.sh git_get_commit_details breaks on a quoted subject and git_conventional_commit_stats drops the oldest commit (workflow-status counts itself); lib info does not list plugin libraries; no framework blueprint fills COMMAND_TOOL_DISPATCH; cli_parse takes the word after an unknown flag as its value.
6. P5 and P6 are outlined; B-2 holds the old slug copies; the classic protection code goes in P6.

## Decided
- D58: rules-sync skips a ruleset whose branch setting is unset and prints skipped; master always applies (T4.5 made rules_json exit 3).
- D59: slash commands are type tool calling bash app git <name> directly; no forwarding scripts; blueprints under commands/blueprints/tool-dispatch/.
- D60: pr, release, promote and rules-sync get disable-model-invocation in this project's commands.claude.yaml only.
- Release ruleset takes its branch from GIT_WORKFLOW_RELEASE_BRANCH, master has the App as bypass (D16, D30). The pre-push hook runs the plugin check.sh, not app git check (no plugin registry in a throwaway project).
- One review per task, findings fixed by hand, no fix rounds.

## Traps
- A failed commit leaves its files staged: a header over 100 characters put code into the plan commit once.
- Agents say shellcheck is not installed; it is in node_modules/.bin. lib info needs the .sh suffix.
- plan amend: replace text literally in python, never jq sub (regex); test the program on a copy.
- dynamic-author can stop early or lose its report: SendMessage it to continue and send the report as plain text.
- No git stash. Never print a token.

## Read first
- Memory: MEMORY.md, feedback-orchestrator-authoring-and-review, feedback-plan-amend-dry-run.
- PLAN-plugin; reports T4.13, T4.6 under the session reports.
