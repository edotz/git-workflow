## State
- PLAN-plugin (B-1) active: P1 to P3 done, P4 detailed as T4.1 to T4.13, none started. Roadmap: m1, m2, m3 done.
- Built and verified earlier: token service, libs token, version, check, component, tool; commands release, promote; linting now runs through toolchain.linters of project.yaml (node with Biome 2.6.5, shell), the plugin lint module is removed and `app lint all full` replaces `app lint node full`; sandbox pilot (v0.1.0, v0.2.0, branch release). plan check clean.
- This session: amended P4 with T4.13 (the /git: slash commands in the plugin tier); T4.12 depends on it and uses them; T4.9 brief takes its tier from hook-target; the P4 gate has the T4.13 verify. Wrote notes/plugin-slash-commands.md.
- Branch chore/git-workflow-concept pushed up to 3c7a393. Uncommitted and ours: PLAN-plugin.json and .md, roadmap.json (m3 done), notes/plugin-slash-commands.md. Not ours: .shellcheckrc (holds our SC2317/SC2329 disable), workflow.env.*.example, docs/git-workflow-*, PDFs, PNGs, 260903 draft, .envrc, output-styles.

## Open
1. START: T4.1 check, T4.2 start, T4.5 rules library (ready); then T4.3, T4.4, T4.6, T4.7, T4.10, T4.11; T4.8 inline; T4.9 hook-author; T4.12 pilot is the developer's.
2. T4.13 waits for the developer's check in the agentic-os project of notes/plugin-slash-commands.md: a script command resolves its script only under bin/commands/ (lib/compiler.sh:477-493), so a plugin cannot ship one. Options in the note: framework change, script "../app git <name>", or no slash commands. Amend T4.13 through /aos:plan after the answer. Unchecked: a compile, app lint on command registrations, whether a session with purpose deliverable can claim T4.13.
3. Confirm D41: the aggregate job in the runner reads components.yaml and runs lint plus checks itself (a runner has no agentic-os).
4. T4.10/T4.11 Done checks are untested sketches; T3.11 closed without review; apply paths of release and promote ran only in the pilot.
5. Backlog: B-2 shared remote slug helper; no item yet for plugin script commands (the shadowing of app lint list is void: the plugin lint domain is gone). PLAN-plugin T3.9 to T3.11 still describe the removed lint module; amend through /aos:plan.
6. /aos:init: declare .docker/, tests/, .env.defaults; widen the root scope trigger.
7. Developer: rotate the GH_TOKEN echoed twice; check .npmrc of edotz.nodejs-project; keep or retire the sandbox; confirm D31; v0.1.0 Release body is empty.

## Decided
- D42 to D44: T4.13 is one P4 task depending on T4.7; seven commands get a slash command (start, commit, pr, check, release, promote, rules-sync); targets come from tiers registration-dir and hook-target, no tier path is written into a brief.
- The project is already registered as a plugin (project.yaml plugins, plugin tier in the chain); the compile never reads the purpose, only authoring does.
- D33: .env.defaults is the fallback, the plugin-root .env overrides pins; one .docker/Dockerfile, root docker-compose.yaml.
- D34 composer.json refused only without a version key; D35 version_next returns 1 when nothing is new; D36 one token_fetch per command run; D37 release commit without repo hooks.
- D38 to D41: commit drafted by provider, start and pr as developer, rules-sync three rulesets as App, one check definition in components.yaml.

## Traps
- No git stash. Port 8790. Never print a token or key. Commit header 100 characters at most.
- gh has no stored login: the exported GH_TOKEN is the developer login. The shell exports RELEASE_BRANCH=0.x, which beats .env: set it on the command line.
- SSH to GitHub fails now and then; gh credential helper over https works.
- Under purpose project, tiers registration-dir prints the project tier; the purpose of a session cannot change, a new session needs --purpose deliverable.
- Tool output can arrive abbreviated: Read the file when exact text matters.
- version_next status 1 means no change: call it inside if.

## Read first
- plan ready, plan facts T4.1; notes plugin-slash-commands, pilot-release, token-service, component-declaration.
- Memory: MEMORY.md, project-sandbox-pilot-setup, feedback-orchestrator-authoring-and-review.
