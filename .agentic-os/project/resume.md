# Handoff plugin (2026-11-12, third close)

## State
- PRs 8 to 16 of edotz/git-workflow are merged, master is at d3054db: squash suffix title lint, 12 manuals in docs/, `app git start` creates the branch in the checkout, branch-cleanup deletes merged branches (lease, github.com only), token service binds loopback, master ruleset follows GIT_WORKFLOW_MAIN_BRANCH, lint-commit --help, plan ledger, the git-workflow skill (plugin tier, three references).
- PLAN-plugin: T6.22 done, D87 (suffix), D88 (T6.20 and T6.21 dropped, continuation plan later). Only T6.19 is pending.
- Unpushed: local branch docs/pre-commit-belongs-to-agentic-os (c9304e6); the push to master was rejected by the ruleset.
- Uncommitted here: settings.local.json and .claude/output-styles/ (not ours).
- Vendor repos typo3-cms and php-project: branch feat/php-8-4-migration, hooks commit-msg and pre-push enabled (hooks.json uncommitted), shims reinstalled, no migration commit yet.
- sdv.bewerber, untracked: bin/composer-dev, docker-compose.vendor-dev.yml, docs/261112-edotz-vendor-repos-during-the-migration.md.

## Open
1. START: the live master ruleset of edotz/git-workflow is production-form, so direct pushes fail in stage development. Run `rules-sync --apply` with stage development (token service, production key) or land the docs branch by PR.
2. Rebuild and restart the token service image (loopback bind of PR 12).
3. T6.19 typo3-cms first release and promote baseline of 2.x after the migration feat merges; then the P6 gate, m6-retire-old done, plan status done.
4. Continuation plan: first releases of php-project and nodejs-project (D88).
5. Leftovers: drift warning for stage versus live ruleset, branch-cleanup still protects release-please-- and backport/, worktree --start accepts an existing branch, git-cliff three docker starts per component.

## Decided
- D86, D87, D88 stand. The migration releases as `feat`, minor: it keeps the 2.x line and sdv ^2.0.
- The pre-commit shim and mapping belong to agentic-os, not the plugin; PR 13 stays.
- One branch via /git:start, logical commits via /git:commit; no worktrees; findings are fixed by hand, no backlog items.
- The skill ships in the plugin tier, trigger by description only, agent playbooks in references, commands as `bash ${BU_ROOT}/app`; manual names must not collide with framework docs.

## Traps
- GIT_WORKFLOW_RELEASE_BRANCH=1.x is exported in the shell over the .env.
- origin is SSH without a key: push by https with the gh credential helper.
- `app git start` needs Docker; when it fails nothing is created, never cherry-pick onto master.
- Subagents inherit memory, so a pressure baseline is contaminated; the classifier denies reading .env.

## Read first
Memory: MEMORY.md, project-git-workflow-live-ruleset-stage-drift, project-sdv-bewerber-driver, reference-production-app, project-token-service-hosting, feedback-daily-loop-branch-not-worktree. PLAN-plugin, docs/README.md.
