## Now
- m6-retire-old: workflow.env, its templates, branch-protection.yaml, all callables and the old reference docs are removed; left are the status-checks.yml header (T4.8), the classic templates and the classic protection code (P6)
- m4-daily-loop: P4 detailed as T4.1 to T4.19, plan reviewed (D54 to D57), only T4.14 done; next group T4.15, T4.18, T4.1, T4.5, then T4.2, T4.3, T4.4, T4.6; the slash commands are T4.16, T4.13, T4.17 (B-62 is done); the pilot T4.12 is the developer's

## Log
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

