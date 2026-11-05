## Now
- m6-retire-old: context wording fixed and committed; the old CI and the classic protection code remain for M6
- m4-daily-loop: P4 detailed as T4.1 to T4.13; next T4.1, T4.2, T4.5, then T4.3, T4.4, T4.6, T4.7; T4.13 waits for the agentic-os check of how a plugin ships script commands; the pilot T4.12 is the developer's

## Log
- 2026-11-05 plugin (a24bcf21): linting moved to toolchain.linters of project.yaml (node Biome, shell); the plugin lint module is removed, `app lint all full` replaces `app lint node full`; plan tasks T3.9 to T3.11 still describe the old module
- 2026-11-04 plugin (a24bcf21): amended P4 with T4.13 for the /git: slash commands, found that a plugin cannot ship a script command, wrote the findings note for the agentic-os check
- 2026-11-04 plugin (a24bcf21): built the token, version and check libraries, release, promote and node lint, ran the sandbox pilot (v0.1.0, v0.2.0), settled findings, set m1 to m3 done, detailed P4
- 2026-11-03 plugin (a24bcf21): finished P2 (pins, image, tool.sh), chose the token service hosting, detailed P3, built the token service as a node module and the component library, added the Biome lint task T3.9
- 2026-11-03 plugin (a24bcf21): checked the GitHub App and tool claims, settled the token service and the component declaration (P1 done), detailed the tool image phase
- 2026-11-02 plugin (a24bcf21): wired the git pre-commit through the plugin, decided the git-workflow-plugin concept, added the roadmap and B-1, fixed the project context

