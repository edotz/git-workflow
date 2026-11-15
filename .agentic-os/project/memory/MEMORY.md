## Now
- m6-retire-old: plan done, PRs 21 to 24 merged; next the sdv.bewerber ^3.0 update, the typo3-cms 2.x and cli/nodejs-project questions, then the nodejs-project first release as a continuation plan

## Log
- 2026-11-13 plugin (a24bcf21): merged PRs 22 to 24 (scope templates, stage warning, worktree and changes fixes, one git-cliff run and a tag cache), kept host git in worktree.sh by design
- 2026-11-13 plugin (a24bcf21): adopted cli, applied the 3.x and legacy rulesets, released php-project and typo3-cms 3.0.0 with 3.x and the legacy freezes, split the children twice, no GitHub Release in monorepos (PR 21), set PLAN-plugin done (T6.19 dropped, D89); PR 22 open
- 2026-11-12 plugin (a24bcf21): reworked /git:start, commit and stage as dialogs (changes and stage commands), fixed the live-ruleset comparison and the PROJECT_ROOT use, switched the live master ruleset to development; PRs 17 to 20 merged
- 2026-11-12 plugin (a24bcf21): merged PRs 8 to 16 (squash suffix lint, manuals, start in the checkout, branch-cleanup deletion, loopback token service, git-workflow skill), prepared the typo3-cms and php-project migration branches and the sdv composer.dev setup, found the live ruleset drift (D87, D88)
- 2026-11-11 plugin (a24bcf21): baselined the ten nodejs-project children and closed their old release PRs, retired the classic protection code, moved git-workflow to rulesets, made version_next count from a range with the feat, fix, perf and breaking filter (D85, D86); PRs 5 to 7 merged
- 2026-11-11 plugin (a24bcf21): migrated typo3-cms (branch roles, 2.x/1.x) and php-project (children baselined, old release train removed), nodejs-project to pnpm and components, added promote baseline, PR title lint, split skip and the split token set (D79 to D84)
- 2026-11-10 plugin (a24bcf21): registered /git:split (T5.4, D77, D78), piloted the monorepo in the sandbox (T5.5) and fixed the push hooks in the tool image, migrated typo3-cms up to its rulesets and merged PRs, cleaned up its branches and protection
- 2026-11-10 plugin (a24bcf21): piloted the daily loop in the sandbox (T4.12), registered the commands, detailed P5 and P6 with a plan review (D61 to D76), built the production App, the rules-sync foreign report and the split dry run and apply (T5.1 to T5.3), cleaned up temp work and memory
- 2026-11-09 plugin (a24bcf21): authored P4 in two rounds with parallel authors and one review each, registered the commands and the pre-push guard, amended the plan (D58 to D60), pushed up to 81f10f2
- 2026-11-09 plugin (a24bcf21): closed the session with the handoff; branch pushed up to c3f182f; the authoring of group 1 is next
- 2026-11-09 plugin (a24bcf21): aligned T4.1, T4.2, T4.5 (D51, D52, T4.15), split T4.13 (D53, T4.16, T4.17), reviewed the plan with five lenses and settled the findings (D54 to D57, T4.18, T4.19), rotated the leaked token and stored a gh login, ignored .envrc, committed and pushed up to the review round
- 2026-11-09 plugin (a24bcf21): T4.14 done (branch settings GIT_WORKFLOW_ keys, workflow-setup reduced to validate), both findings accepted, project .env sets master and 0.x
- 2026-11-09 plugin (a24bcf21): amended the plan (T4.14 branch settings to GIT_WORKFLOW_ keys, D45 to D48, P3 gate fixed, D41 confirmed), dropped _callable-status-checks.yml, one env bash shebang for ide scripts and templates, compiled; plan amend --dry-run writes the plan
- 2026-11-05 plugin (a24bcf21): re-ran init (docker scope declared, architecture.md updated), removed workflow.env, its templates, the protection config and the release callables, ignored the planning locks, committed and pushed
- 2026-11-05 plugin (a24bcf21): linting moved to toolchain.linters of project.yaml (node Biome, shell); the plugin lint module is removed, `app lint all full` replaces `app lint node full`; plan tasks T3.9 to T3.11 still describe the old module

