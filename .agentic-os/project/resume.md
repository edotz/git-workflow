# Handoff plugin (2026-11-11, second close)

## State
- PLAN-plugin B-1: every task of P1 to P6 is done except the developer tasks T6.19 to T6.21. PRs 5, 6 and 7 of edotz/git-workflow are merged; master is at 4d90824; nothing is uncommitted but .claude/output-styles/ (not ours).
- Built and verified this session: nodejs-project (ten children baselined with legacy/pre-split, notes migrate-nodejs-pnpm.md and migrate-nodejs-project.md, four old release-please PRs closed and six release-please branches deleted in the children); classic protection code, run-status and the heredoc templates retired, workflow-status has a runs field (T6.7); project context in the new wording (T6.8); git-workflow itself has rulesets master and release (1.x), squash on, classic protection gone (T6.13); components.yaml of the plugin and the pushed baseline tag v0.1.0 (T6.18); version_next counts the commits after the latest tag and only feat, fix, perf and breaking (T6.17, bin/config/cliff.toml, tests/git-version/range.sh).

## Open (first one is next)
1. START: add a task through /aos:plan for the squash subject: GitHub appends " (#N)", so a title of 96 or more characters passes the title lint and fails the commit lint on master (PR 5 became 101 characters); lint title plus the suffix in pr.sh and status-checks.yml.
2. T6.19 to T6.21 (developer): first release per repo, then app git promote <tag> baseline of the release branch (typo3-cms 2.x, php-project 2.x, nodejs-project 1.x, D81). Each waits for a feat, fix, perf or breaking commit after its baseline. Check first whether the changes of the closed release PRs (utilities 2.0.0 with a breaking change) are in the baselined versions; the monorepo history holds no commit with their messages.
3. After them: gate of P6, milestone m6-retire-old to done, plan status done.
4. Leftovers: branch-cleanup still protects release-please-- and backport/ branches; github_get_file_contents has no caller; git-cliff runs three docker starts per component (--bump --context could merge two).

## Decided, do not reopen
- D85 new tasks go into P6, not a P7: they finish the migration (D81). D86 only feat, fix, perf and breaking commits release: a ci or chore commit in a package no longer bumps a patch.
- Daily loop: a branch in the main checkout (git switch -c from master, then git branch --unset-upstream), not a worktree per change.
- Children follow the monorepo; D79 to D84 stand.

## Traps
- The shell exports GIT_WORKFLOW_RELEASE_BRANCH=0.x over the .env, so branch-cleanup --force would delete 1.x; find the export before using it.
- origin is an SSH URL and the session has no key: fetch and push by https with -c credential.helper='!gh auth git-credential' (app git pr does this itself).
- app git pr derives the PR title from the branch name; name the branch like the subject. Never gh pr create --fill.
- Classifier denies background loops and destructive applies unless the allow rule in .agentic-os/adapters/claude/templates/settings.local.json is live; reading .env is denied.
- git-cliff takes --include-path with several values: put the range before it; the config goes over stdin (tool_run mounts the repo only).
- Commit headers over 100 characters are refused by lint-commit; plan amend --dry-run writes.

## Read first
Memory: MEMORY.md, project-nodejs-project-migration-state, project-php-project-migration-state, project-typo3-cms-migration-state, reference-production-app, project-token-service-hosting. PLAN-plugin, notes migrate-nodejs-project.md and app-production.md.
