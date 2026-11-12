## Now
- m6-retire-old: all P6 tasks but T6.19 to T6.21 done; next a task for the squash subject limit, then the first releases and promote baseline per repo, then close the plan

## Log
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
- 2026-11-04 plugin (a24bcf21): amended P4 with T4.13 for the /git: slash commands, found that a plugin cannot ship a script command, wrote the findings note for the agentic-os check
- 2026-11-04 plugin (a24bcf21): built the token, version and check libraries, release, promote and node lint, ran the sandbox pilot (v0.1.0, v0.2.0), settled findings, set m1 to m3 done, detailed P4
- 2026-11-03 plugin (a24bcf21): finished P2 (pins, image, tool.sh), chose the token service hosting, detailed P3, built the token service as a node module and the component library, added the Biome lint task T3.9
- 2026-11-03 plugin (a24bcf21): checked the GitHub App and tool claims, settled the token service and the component declaration (P1 done), detailed the tool image phase
- 2026-11-02 plugin (a24bcf21): wired the git pre-commit through the plugin, decided the git-workflow-plugin concept, added the roadmap and B-1, fixed the project context

