# Handoff plugin (2026-11-13, sixth close)

## State
- PLAN-plugin is done. PRs 21 to 24 are merged: no GitHub Release in a repository of several components; scope templates; stage warns about a drifted release or legacy ruleset, worktree --start refuses an existing branch (branch_refuse_existing), changes stops on a newline path; version_next counts and bumps in one git-cliff run and version_latest_tag keeps its answer until version_cache_reset. Master is e239deb, local branches deleted, token service stopped.
- Migration released: typo3-cms v3.0.0 and the eight php-project components 3.0.0, 3.x created by promote, children split twice. Rulesets of both repos: release 3.x, legacy 1.x,2.x. edotz.cli adopted, no release.
- Uncommitted here: .agentic-os/project memory, resume, roadmap, PLAN-plugin.json and .md. sdv.bewerber: docs/261112-edotz-vendor-repos-during-the-migration.md updated, uncommitted there.

## Open
1. START: sdv.bewerber: constraints to ^3.0, vcs entries, composer update; bin/composer-dev line 32 writes ^2.0; D9 of PLAN-migration-02 names 2.x (amend with /aos:plan there).
2. Questions for the developer: what typo3-cms 2.x holds (published v2.0.x need TYPO3 13.4 and PHP 8.2); whether cli and nodejs-project follow the 3.x scheme.
3. Continuation plan: first release of nodejs-project (D88); cli only if the migration changes it.
4. Compile the framework so .claude/rules shows the refreshed templates; commit the .agentic-os/project files on a chore branch (master takes no direct push).
5. Left: the form command type belongs to edotz.claude-code; APP_KEY_PATH in the token-service test stays.

## Decided
- The migration ships as major releases; 1.x and 2.x legacy, 3.x release branch; promote creates 3.x, 2.x is never moved (D89, project-major-release-branch-roles).
- Only a repository of one component makes a GitHub Release; Composer reads the tags of the children.
- worktree.sh and branch.sh keep host git: they work on the developer's checkout and git worktree add cannot run in the tool image (the worktree sits outside the mount). Not a defect.
- The apply notes are not reused for the GitHub Release: git-cliff writes the file or prints, so reuse would parse CHANGELOG.md for no saving.
- stage only warns about release and legacy; the apply still switches master only.
- A task is never superseded: the schema has dropped.

## Traps
- This agent shell exports BU_BOOTSTRAPPED, PROJECT_ROOT and GIT_WORKFLOW_*: a module run in a throwaway repo works on the real one, and app git in another repo skips its .env. Use env -u PROJECT_ROOT, unset them per repo.
- A cache set inside $( ) is lost: version_next and version_latest_tag set VERSION_NEXT and VERSION_LATEST_TAG.
- die expands a backslash-n in its message: print a newline as <LF>.
- Two tags on one commit: git describe picks the older; a test needs a new commit before the second tag.
- After a pull by URL origin/master is stale: fetch '+refs/heads/master:refs/remotes/origin/master'. origin is SSH without a key: push and pull by https with the gh credential.
- app git pr takes the title of the commit; a squash merge keeps only the subject for git-cliff.

## Read first
Memory: MEMORY.md, project-plugin-open-leftovers, project-major-release-branch-roles, project-sdv-bewerber-driver, reference-production-app, project-token-service-hosting, feedback-pr-title-via-git-pr. The sdv.bewerber doc above.
