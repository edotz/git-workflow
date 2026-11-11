# Handoff plugin (2026-11-11)

## State
- PLAN-plugin B-1: P1 to P5 done. P6 done: T6.1, T6.2, T6.3, T6.5, T6.9 to T6.12, T6.14 to T6.16. Pending: T6.4, T6.6 (notes missing), T6.13, T6.7, T6.8.
- Built and verified this session: promote baseline mode (T6.9), PR title lint in pr.sh and status-checks (T6.10), pre-push shim test (T6.11), split skips a child tag at another commit (T6.14), commitlint decides alone (T6.15), token set split with workflows write (T6.16, image rebuilt, container stopped). tests git-promote, git-pr, git-shims, git-split, git-commit pass; shellcheck clean.
- Migrated: typo3-cms (master, rulesets, 2.x release, 1.x legacy, PRs 72 to 75, draft release deleted). php-project (T6.5 done: PR 70, 71, 72, rulesets, eight children baselined and cleaned, baseline tags on 6f6acc4). nodejs-project: PR 18 (pnpm), PR 19 (components, workspace field), rulesets master and release 1.x, classic protection gone, ten baseline tags on 721da35.
- Branch chore/git-workflow-concept is pushed; uncommitted: ledger files, .claude/output-styles.

## Open (first one is next)
1. START: nodejs-project child baselines. Start the token service with the production key, run from ~/worktrees/nodejs-project-clone with pnpm 10 on PATH and env overrides (GIT_WORKFLOW_APP_ID=5694393, STAGE=production, MAIN_BRANCH=master, RELEASE_BRANCH=1.x): data-handler first, then nine, one per run, --confirm edotz/<name>. data-handler already has legacy/pre-split.
2. Write notes migrate-nodejs-pnpm.md (T6.4) and migrate-nodejs-project.md (T6.6), record both. Hoist, --npm-path npm, token set split, workflows permission belong in them.
3. T6.13 classic protection of master of this repo, T6.7, T6.8 (also stale bin-modules.md lint-bypass note).
4. Open amends: version.sh range instead of tag-on-path (a ci commit after a baseline tag bumps a patch); first real release then the 2.x/1.x baseline move with promote baseline (D81) in typo3-cms, php-project, nodejs-project.

## Decided, do not reopen
- D79 release branch keeps its name (2.x typo3-cms and php-project, 1.x nodejs-project), moved once by promote baseline. D80/D82 legacy lines frozen, tag legacy/1.x-freeze, classic protection removed before the cleanup PR. D81 promote baseline. D83 split skips a child tag at another commit, never moves it. D84 token set split only for the split apply.
- Children follow the monorepo: master is the split target, 1.x/2.x and old tags stay.
- Commit lint has no Merge/Revert bypass (like CI).

## Traps
- Shell exports GIT_WORKFLOW_*, PROJECT_ROOT, AOS_PLUGIN_TIERS: use env -u or overrides in other repos; never cat .env.
- The tool image cannot run git in a linked worktree: use real clones. Baseline tags on a commit at or after the last cleanup of the package dirs.
- A permission granted to the App is not enough: the token set must carry it, the image holds the config (rebuild).
- Classifier denies pushes to master, merges, protection removal at times; shell grep is a ugrep function (use command grep).
- Pull requests only through app git pr (title linted); raw gh pr create --fill produced a bad squash title once.

## Read first
Memory: MEMORY.md, project-nodejs-project-migration-state, project-php-project-migration-state, project-typo3-cms-migration-state, reference-production-app, project-token-service-hosting, feedback-pr-title-via-git-pr. PLAN-plugin, notes migrate-typo3-cms.md and migrate-php-project.md.
