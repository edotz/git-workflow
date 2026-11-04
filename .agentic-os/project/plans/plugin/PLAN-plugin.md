# PLAN-plugin
Generated from PLAN-plugin.json, do not edit.

**Goal:** Settle the foundations of the git-workflow plugin (the checked GitHub and tool behaviours, the token service and the component declaration) so that the tool image, release core, daily loop, monorepo and retirement phases can be detailed on checked ground.

## Abstract

### Summary

The plan opens the git-workflow plugin by closing what the milestone m1-foundations asks for: every verify claim of the white paper is checked against GitHub and the real tools, the token service interface, developer authentication, hosting and key custody are settled, and the component declaration is settled. Later phases for the tool image, release core, daily loop, monorepo and retirement are outlined only, one per later milestone of the roadmap.

### Outcome

Five notes in the concept's notes directory, one of them recording the sandbox: one with a row per marked line of the white paper for the GitHub App behaviours, one for the tool and ecosystem claims, one for the token service contract with authentication, fallback and hosting, and one for the component declaration with its path resolution and pre-release handling. The milestone gate of m1-foundations can then be read off these notes.

### Phases

- P1 Foundations: checked claims, token service, component declaration: 5 tasks
- P2 Tool image: 4 tasks
- P3 Release core: 9 tasks
- P4 Daily loop and guards: 0 tasks
- P5 Monorepo: 0 tasks
- P6 Retire the old approach: 0 tasks

### Cost

Nine tasks in the detailed phases: the five tasks of P1, all done, and four in P2 (pins, Dockerfile and compose file, the library function, the clean machine check). The four outlined phases after P2 cost nothing until they are detailed in an amend.

### Decisions to confirm

none

### Open points

none

### Risks

Several GitHub behaviours the release rests on are unverified and may be refuted, which would change decided concept decisions (the App as the only bypass actor, the GitHub Release created by the App, --latest=false). T1.1 needs a test GitHub App and a sandbox repository that the developer registers first. The token service has no design yet and every remote write depends on it. The white paper marks 18 lines against the concept's 13 claims; the plan covers all 18 and does not reconcile the concept's count.

### Success

Each marked line of the white paper has a row with a result and evidence, each refuted claim names the decision it puts in doubt, and the developer can read the token service contract and the component declaration as settled. The milestone m1-foundations gate can then be called met.

**Track:** deliberative  **Items:** B-1
**Status:** active  **Mode:** subagents

## P1 Foundations: checked claims, token service, component declaration (detailed)

| Title | Task | Owner | Depends | Status |
|---|---|---|---|---|
| Register the test GitHub App and sandbox repository | T1.0 | developer | - | done |
| Check the GitHub App behaviours the release depends on in a sandbox repository | T1.1 | developer | T1.0 | done |
| Check the tool and ecosystem claims of the white paper against current documentation and the real tools | T1.2 | inline | - | done |
| Settle the token service contract, developer authentication, fallback and hosting | T1.3 | inline | T1.1 | done |
| Settle the component declaration, its path resolution and pre-release handling | T1.4 | inline | T1.2 | done |

**Register the test GitHub App and sandbox repository** (T1.0)
- Why: The checks of the App behaviours cannot run without an App and a repository that the project does not yet hold; plan decision D3 puts this before the first check, so a task enforces the order.
- Result: A note that names the test App, the sandbox repository and the settings the checks run under.
- Done: The note exists with the three sections, and the Settings section names the ruleset level and the plan tier.
- Fails: T1.1 would start without an App or a repository, or run against settings that differ from the consuming projects without saying so.

**Check the GitHub App behaviours the release depends on in a sandbox repository** (T1.1)
- Why: The release design depends on GitHub behaviours that nobody has checked; the concept names them as the first thing the plan verifies. This task has the most unknowns, so it comes first and a refuted claim shows before anything is built on it.
- Result: A report with one row per marked line, each with a result and the evidence behind it.
- Done: The report file exists and holds a row for each of the eleven lines; each row ends in confirmed, refuted or changed, names how it was run, and a refuted or changed row names the concept decision it puts in doubt.
- Fails: The release commit, the tag, the GitHub Release by the App and the single required check would be built on unchecked behaviour and could fail only when the first project releases.
- Carries: What the development phase of STAGE relaxes on master (CONCEPT-git-workflow-plugin:D29); Who may make the release commit, the tag and the promote (CONCEPT-git-workflow-plugin:D30); How the GitHub Release is created (CONCEPT-git-workflow-plugin:D40); How one latest release per repository works with several components (CONCEPT-git-workflow-plugin:D56)

**Check the tool and ecosystem claims of the white paper against current documentation and the real tools** (T1.2)
- Why: The image base, the version-file writers and the pre-release handling cannot be decided on claims nobody checked; these claims need no GitHub account, so they run independently of the GitHub checks.
- Result: A report with one row per marked line, each with a result, the version checked and the evidence.
- Done: The report file exists and holds a row for each of the seven lines, each with a result of confirmed, refuted or changed and a named method.
- Fails: The image could get a base the splitsh-lite binary does not run on, and the version writers and the pre-release rule would be built on a guess.
- Carries: What the container does (CONCEPT-git-workflow-plugin:D34); The versioning unit and the tag format (CONCEPT-git-workflow-plugin:D38); Where the plugin ends (CONCEPT-git-workflow-plugin:D39); How pre-releases are handled (CONCEPT-git-workflow-plugin:D47); Which writers align the version files (CONCEPT-git-workflow-plugin:D50); How the modules call the tool image (CONCEPT-git-workflow-plugin:D55)

**Settle the token service contract, developer authentication, fallback and hosting** (T1.3)
- Why: Every remote write (release, promote, split, rules-sync) needs a token from the service; without a settled contract the library that fetches the token cannot be planned.
- Result: A note that states the contract between the CLI and the token service, how a developer is authenticated, what happens when the service is unavailable, and where the service runs.
- Done: The note exists with the four sections and cites the App permissions of row L500; Client contract, Authentication, Fallback and the key custody state decided answers, and Service hosting states the platform requirements and names the platform as deferred by decision D15.
- Fails: The GitHub library cannot be designed, and the first release would stall on the question of where its token comes from.
- Carries: Replacement of the personal access token (CONCEPT-git-workflow-plugin:D4); How the CLI obtains the app token (CONCEPT-git-workflow-plugin:D6); How the token service is designed (CONCEPT-git-workflow-plugin:D23); How the token service authenticates a developer (CONCEPT-git-workflow-plugin:D48)

**Settle the component declaration, its path resolution and pre-release handling** (T1.4)
- Why: The release, the split and the aggregate check all read the component declaration; they cannot design their data interfaces until its format is fixed. The roadmap gate of this milestone names it.
- Result: A note that fixes the declaration's fields, how a component's paths are resolved, how a pre-release is handled and how a single repository is declared.
- Done: The note exists with the four sections, cites row L390 for the pre-release rule, and each section states a decided answer.
- Fails: The release, split and check modules would each guess the declaration's shape, and the old PACKAGES_DIR and per-package env files would stay.
- Carries: The versioning unit and the tag format (CONCEPT-git-workflow-plugin:D38); The format of the component declaration (CONCEPT-git-workflow-plugin:D44); Whether JS components take their paths from the workspace graph (CONCEPT-git-workflow-plugin:D46); How pre-releases are handled (CONCEPT-git-workflow-plugin:D47)

Gate: (f=.agentic-os/project/concepts/git-workflow-plugin/notes/sandbox.md; test -s $f && grep -q '^## Repository' $f && grep -q '^## App' $f && grep -q '^## Settings' $f) && (f=.agentic-os/project/concepts/git-workflow-plugin/notes/verify-github.md; for l in 261 316 411 441 467 470 491 500 520 523 654; do grep -qE "^[|] L${l} [|][^|]*[|][^|]*[|][[:space:]]*(confirmed|refuted|changed)[[:space:]]*[|][^|]*[^|[:space:]][^|]*[|][[:space:]]*\$" $f || exit 1; done; [ "$(grep -E '^[|] L[0-9]+ [|][^|]*[|][^|]*[|][[:space:]]*(refuted|changed)[[:space:]]*[|]' $f | grep -cvE 'D[0-9]+')" = 0 ]) && (f=.agentic-os/project/concepts/git-workflow-plugin/notes/verify-tools.md; for l in 237 239 390 460 595 624 786; do grep -qE "^[|] L${l} [|][^|]*[|][^|]*[|][[:space:]]*(confirmed|refuted|changed)[[:space:]]*[|][^|]*[^|[:space:]][^|]*[|][[:space:]]*\$" $f || exit 1; done) && (f=.agentic-os/project/concepts/git-workflow-plugin/notes/token-service.md; test -s $f && grep -q '^## Client contract' $f && grep -q '^## Authentication' $f && grep -q '^## Fallback' $f && grep -q '^## Service hosting' $f && grep -q 'L500' $f && ! grep -qiE 'TBD|TODO|open question' $f) && (f=.agentic-os/project/concepts/git-workflow-plugin/notes/component-declaration.md; test -s $f && grep -q '^## Fields' $f && grep -q '^## Path resolution' $f && grep -q '^## Pre-releases' $f && grep -q '^## Single repository' $f && grep -q 'L390' $f && ! grep -qiE 'TBD|TODO|open question' $f)

## P2 Tool image (detailed)

| Title | Task | Owner | Depends | Status |
|---|---|---|---|---|
| Pin the tool versions, the base image digest and the checksums in the plugin settings | T2.1 | inline | - | done |
| Rebuild the Dockerfile and the compose file on the pinned base | T2.2 | inline | T2.1 | done |
| Write the library function that runs a tool through the image | T2.3 | bash-author | T2.1, T2.2 | done |
| Run the tools on a machine that has neither the tools nor the image | T2.4 | developer | T2.3 | done |

**Pin the tool versions, the base image digest and the checksums in the plugin settings** (T2.1)
- Why: Every later task reads these values; without them the image cannot be reproduced and the build cannot verify a download. Decision D55 asks for the base pinned by digest and each download by checksum.
- Result: The settings file holds one pin per tool and the base image, each with its checksum where the tool is a download.
- Done: Each of the nine keys is present, the base reference ends in a sha256 digest, the platform is linux/amd64, and each checksum has the length of its hash.
- Fails: The Dockerfile would pin nothing or invent its own values, and two machines could build different tools under the same tag.
- Carries: What the container does (CONCEPT-git-workflow-plugin:D34); How the modules call the tool image (CONCEPT-git-workflow-plugin:D55)

**Rebuild the Dockerfile and the compose file on the pinned base** (T2.2)
- Why: The image is the single toolbox of every release and split; the present Dockerfile cannot build (its splitsh-lite URL returns 404) and contradicts decisions D34 and D55.
- Result: A Dockerfile and a compose file that build the pinned toolbox: git, gh, git-cliff and splitsh-lite on a glibc slim base, nothing else.
- Done: The image builds without cache from the pins, git-cliff, gh and git report the pinned versions, splitsh-lite splits a test repository, and the image holds no Node and no provider CLI.
- Fails: The library function would call an image that does not build, and the first release would fail at its tool call.
- Carries: What the container does (CONCEPT-git-workflow-plugin:D34); How the modules call the tool image (CONCEPT-git-workflow-plugin:D55)

**Write the library function that runs a tool through the image** (T2.3)
- Why: One function builds every tool call, so the version pins, the mounts and the token handling exist in one place; the release, split and rules-sync commands of later phases call it.
- Result: A library function that runs git, gh, git-cliff and splitsh-lite through the pinned image in an ephemeral container, in a repository and in a worktree.
- Done: tool_run runs git and git-cliff through the image in a plain repository and in a worktree, passes bash -n, and builds the image on first use when it is missing.
- Fails: Each command would assemble its own docker call, the mounts and the token handling would diverge, and a worktree would fail with 'not a git repository'.
- Carries: Whether the modules use a host binary or docker only (CONCEPT-git-workflow-plugin:D35); How the modules call the tool image (CONCEPT-git-workflow-plugin:D55)
- Produces: tool_run tool_run <tool> [args...]
- Produces: tool_image_ensure tool_image_ensure

**Run the tools on a machine that has neither the tools nor the image** (T2.4)
- Why: The gate of the milestone asks for the tools to run through docker on a clean machine at the pinned versions; only a machine that never built the image shows that the build is reproducible.
- Result: A note that names the machine and shows the three tools running at the pinned versions after a first build.
- Done: The note names the machine and the result, and the host path holds neither git-cliff nor splitsh-lite.
- Fails: The reproducibility would rest on the machine that wrote the Dockerfile, where a local cache or an installed tool can hide a missing pin.
- Carries: What the container does (CONCEPT-git-workflow-plugin:D34); How the modules call the tool image (CONCEPT-git-workflow-plugin:D55)
- Consumes: T2.3 tool_run tool_run <tool> [args...]
- Consumes: T2.3 tool_image_ensure tool_image_ensure

Gate: (f=.env.defaults; for k in IMAGE_BASE IMAGE_PLATFORM GIT_CLIFF_VERSION GIT_CLIFF_SHA512 SPLITSH_VERSION SPLITSH_SHA256 GH_VERSION GH_SHA256 GIT_APT_VERSION; do grep -qE "^${k}=.+" $f || exit 1; done; grep -qE '^IMAGE_BASE=.*@sha256:[0-9a-f]{64}$' $f && grep -qE '^IMAGE_PLATFORM=linux/amd64$' $f && grep -qE '^GIT_CLIFF_SHA512=[0-9a-f]{128}$' $f && grep -qE '^SPLITSH_SHA256=[0-9a-f]{64}$' $f && grep -qE '^GH_SHA256=[0-9a-f]{64}$' $f) && (set -a; . ./.env.defaults; set +a; docker compose --env-file .env.defaults build --no-cache tools && docker compose --env-file .env.defaults run --rm tools git-cliff --version | grep -q "git-cliff ${GIT_CLIFF_VERSION#v}" && docker compose --env-file .env.defaults run --rm tools gh --version | grep -q "gh version ${GH_VERSION#v}" && docker compose --env-file .env.defaults run --rm tools dpkg -s git | grep -q "^Version: ${GIT_APT_VERSION}$" && docker compose --env-file .env.defaults run --rm -e GIT_AUTHOR_NAME=t -e GIT_AUTHOR_EMAIL=t@example.com -e GIT_COMMITTER_NAME=t -e GIT_COMMITTER_EMAIL=t@example.com tools sh -c 'cd /tmp && git init -q r && cd r && mkdir p && echo a > p/f && git add . && git commit -q -m x && splitsh-lite --prefix=p 2>/dev/null' | grep -qE '^[0-9a-f]{40}$' && ! docker compose --env-file .env.defaults run --rm tools sh -c 'command -v node || command -v claude || command -v gemini') && (bash -n bin/lib/tool.sh && PLUGIN_ROOT=$PWD bash -c 'set -euo pipefail; source "${BU_ROOT}/lib/core.sh"; source bin/lib/tool.sh; tool_run git --version | grep -q "^git version"; tool_run git-cliff --version | grep -q "^git-cliff"; t=$(mktemp -d); git -C "$t" init -q r; git -C "$t/r" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m x; git -C "$t/r" worktree add -q "$t/w" -b w; (cd "$t/w" && tool_run git rev-parse --is-inside-work-tree | grep -q true); rm -rf "$t"') && (f=.agentic-os/project/concepts/git-workflow-plugin/notes/tool-image-check.md; test -s $f && grep -q '^## Machine' $f && grep -q '^## Result' $f && ! command -v git-cliff >/dev/null && ! command -v splitsh-lite >/dev/null)

## P3 Release core (detailed)

Build release --dry-run and --apply with the minimum check, the version-file writers, the local README generation, the GitHub Release by the App and promote to the release tag (roadmap milestone m3-release-core).

| Title | Task | Owner | Depends | Status |
|---|---|---|---|---|
| Build the token service container | T3.1 | inline | - | done |
| Write the library that fetches the installation token | T3.2 | bash-author | T3.1, T2.3 | done |
| Write the component declaration library | T3.3 | bash-author | - | done |
| Write the version library: next version, pre-release and the version files | T3.4 | bash-author | T3.3, T2.3 | done |
| Write the minimum check | T3.5 | bash-author | T3.3, T2.3 | done |
| Write the release command: dry run and apply | T3.6 | bash-author | T3.2, T3.3, T3.4, T3.5 | pending |
| Write the promote command | T3.7 | bash-author | T3.2, T3.6 | pending |
| Release and promote a pilot in the sandbox | T3.8 | developer | T3.1, T3.6, T3.7 | pending |
| Write the Node lint command with Biome | T3.9 | bash-author | T3.1, T3.4 | pending |

**Build the token service container** (T3.1)
- Why: Every remote write of the release core (release commit push, tag, GitHub Release, promote) needs an installation token, and the service that issues it does not exist yet; decisions D25 and D26 fix where it runs.
- Result: A container image and a compose file that run the token service on this machine against the sandbox App, with its own check script.
- Done: The image builds; with the sandbox key mounted, a request for edotz/git-workflow-sandbox with the developer's gh login returns a token that holds contents write and metadata read on that repository only; an invalid login token, a repository without the installation and an unknown permission set are refused with a named reason; the container log holds no token.
- Fails: The release commands cannot push as the App, or a token issued too wide, or a token or the key lands in an image or a log.
- Carries: Replacement of the personal access token (CONCEPT-git-workflow-plugin:D4); How the CLI obtains the app token (CONCEPT-git-workflow-plugin:D6); Who may make the release commit, the tag and the promote (CONCEPT-git-workflow-plugin:D30)

**Write the library that fetches the installation token** (T3.2)
- Why: One function fetches the token so that no command assembles its own request and fail-closed is decided in one place; the release and promote commands call it before their first write.
- Result: A library that fetches a narrowed installation token from the local service and hands it to the tool call by variable name.
- Done: token_fetch and token_drop exist, pass bash -n, and with the service unreachable token_fetch exits non-zero with 'service unreachable' and leaves GH_TOKEN unset.
- Fails: A command would write without a token fetched first, or would fall back to a personal token, or a token would reach a log line or an argument.
- Carries: Replacement of the personal access token (CONCEPT-git-workflow-plugin:D4); How the CLI obtains the app token (CONCEPT-git-workflow-plugin:D6)
- Produces: token_fetch token_fetch <owner/repo> <permission-set>
- Produces: token_drop token_drop

**Write the component declaration library** (T3.3)
- Why: The release, the split and the aggregate check all read the component declaration; one library holds its rules and its path resolution so no command guesses the shape.
- Result: A library that loads and validates components.yaml and resolves a component's directories.
- Done: A valid declaration loads and shows its defaults; a declaration with both workspace and paths, and one with an unknown field, are refused; the library passes bash -n.
- Fails: Each command would parse the declaration its own way, and a malformed declaration would be accepted until a release fails halfway.
- Carries: The versioning unit and the tag format (CONCEPT-git-workflow-plugin:D38); The command surface and the fate of the seven existing commands (CONCEPT-git-workflow-plugin:D41)
- Produces: component_load component_load <file>
- Produces: component_names component_names
- Produces: component_paths component_paths <name>
- Produces: component_field component_field <name> <field>

**Write the version library: next version, pre-release and the version files** (T3.4)
- Why: The release commit needs one place that computes the version, the tag and the file rewrite exactly as the declaration note decided, so dry run and apply cannot disagree.
- Result: A library that computes the next version and tag of a component and writes and verifies its version files.
- Done: On a throwaway repository with the tag v1.0.0 and one feat commit, version_next prints 1.1.0 and with channel rc 1.1.0-rc.1, version_write puts 1.1.0 into package.json and reads it back, and version_tag prints v1.1.0.
- Fails: A tag would not match the version file, a pre-release would restart or skip a counter, or a version file would silently keep the old value.
- Carries: Whether master carries the version (CONCEPT-git-workflow-plugin:D33); The versioning unit and the tag format (CONCEPT-git-workflow-plugin:D38); Where the plugin ends (CONCEPT-git-workflow-plugin:D39)
- Produces: version_next version_next <component> [channel]
- Produces: version_write version_write <component> <version>
- Produces: version_tag version_tag <component> <version>
- Consumes: T3.3 component_paths component_paths <name>
- Consumes: T3.3 component_field component_field <name> <field>

**Write the minimum check** (T3.5)
- Why: The release requires the minimum check green on HEAD, so a broken commit message or a failing quick check stops a release before anything is written.
- Result: A library that runs the commit lint and the declared quick checks for a component.
- Done: On a throwaway repository a conventional history with a passing check command passes check_minimum, and after a commit with a message that breaks the rule check_minimum exits non-zero.
- Fails: A release would go out over a commit that the commit-msg hook never saw, or over a failing project check.
- Carries: Where the minimum check for quality runs (CONCEPT-git-workflow-plugin:D32)
- Produces: check_minimum check_minimum <component>
- Consumes: T3.3 component_field component_field <name> <field>

**Write the release command: dry run and apply** (T3.6)
- Why: The release is the heart of the workflow: one local command that makes the release commit, the tag and the GitHub Release as the App, with a dry run that shows exactly what apply would do.
- Result: The command app git release with dry run and apply that makes the release commit, the tag and the GitHub Release.
- Done: The dry run on a throwaway repository prints the next version, the tag and the notes and leaves the working tree and the tags unchanged; the module registry and the script agree. The apply path is checked by the pilot of T3.8.
- Fails: A release would write before its token is fetched, a dry run would differ from apply, or a repeated apply would create a second commit or release.
- Carries: Where the release commit is made (CONCEPT-git-workflow-plugin:D28); Who may make the release commit, the tag and the promote (CONCEPT-git-workflow-plugin:D30); Where the minimum check for quality runs (CONCEPT-git-workflow-plugin:D32); Whether master carries the version (CONCEPT-git-workflow-plugin:D33); How the GitHub Release is created (CONCEPT-git-workflow-plugin:D40); The command surface and the fate of the seven existing commands (CONCEPT-git-workflow-plugin:D41); Goal for the changelog (CONCEPT-git-workflow-plugin:D7); Goal of the work (CONCEPT-git-workflow-plugin:D15)
- Consumes: T3.2 token_fetch token_fetch <owner/repo> <permission-set>
- Consumes: T3.3 component_load component_load <file>
- Consumes: T3.4 version_next version_next <component> [channel]
- Consumes: T3.4 version_write version_write <component> <version>
- Consumes: T3.4 version_tag version_tag <component> <version>
- Consumes: T3.5 check_minimum check_minimum <component>

**Write the promote command** (T3.7)
- Why: Master carries the release commit and the release branch follows only by promote, so a commit pushed to master after a release can never reach the release branch.
- Result: The command app git promote that fast-forwards the release branch to a release tag.
- Done: On a throwaway repository the dry run names the tag's commit as the target and a diverged release branch is refused; the module registry and the script agree. The push path is checked by the pilot of T3.8.
- Fails: A promote would move the release branch to the head of master, or would force a diverged branch.
- Carries: How a promotion reaches the release branch (CONCEPT-git-workflow-plugin:D27); Who may make the release commit, the tag and the promote (CONCEPT-git-workflow-plugin:D30); The command surface and the fate of the seven existing commands (CONCEPT-git-workflow-plugin:D41); What promote fast-forwards the release branch to (CONCEPT-git-workflow-plugin:D52); Where the target branch of a promotion comes from (CONCEPT-git-workflow-plugin:D16)
- Consumes: T3.2 token_fetch token_fetch <owner/repo> <permission-set>

**Release and promote a pilot in the sandbox** (T3.8)
- Why: The gate of m3-release-core asks that a pilot single repository releases locally with commit, tag and GitHub Release by the App and that promote fast-forwards the release branch; only a run against GitHub shows it.
- Result: A note that records a pilot release and promote in the sandbox repository.
- Done: The note names the repository and the result: the tag, the release commit, the GitHub Release made by the App, the harmless repeated apply and the release branch at the tag.
- Fails: The apply and push paths, which the earlier checks cannot reach without GitHub, would first run in a consuming project.
- Carries: How the GitHub Release is created (CONCEPT-git-workflow-plugin:D40); What promote fast-forwards the release branch to (CONCEPT-git-workflow-plugin:D52)

**Write the Node lint command with Biome** (T3.9)
- Why: The plugin now holds Node code (the token service) that the framework's lint commands do not check; one Biome command keeps it linted the same way as the shell scripts and the way the consuming projects already lint theirs.
- Result: A lint command app lint node that runs Biome over the Node files of the plugin in the usual modes.
- Done: app lint node full exits 0 on the plugin as it stands, a throwaway file with known Biome findings makes app lint node specific exit non-zero, and the registry and the script agree.
- Fails: Node files would go unlinted, or the command would pass a file with findings, or a host Biome of another version would give different results on two machines.
- Carries: The command surface and the fate of the seven existing commands (CONCEPT-git-workflow-plugin:D41)

Gate: (test -x bin/modules/git/token-service.mjs && node --check bin/modules/git/token-service.mjs && docker compose --env-file .env.defaults build token-service && bash tests/token-service/check.sh) && (bash -n bin/lib/token.sh && d=$(mktemp -d) && printf '#!/bin/sh\necho devtoken\n' > "$d/gh" && chmod +x "$d/gh" && PATH="$d:$PATH" env -u GH_TOKEN PLUGIN_ROOT=$PWD bash -c 'set -euo pipefail; source "${BU_ROOT}/lib/core.sh"; source bin/lib/token.sh; declare -F token_fetch >/dev/null; declare -F token_drop >/dev/null; out=$(TOKEN_SERVICE_URL=http://127.0.0.1:9 token_fetch edotz/git-workflow-sandbox contents 2>&1) && exit 1; printf "%s" "$out" | grep -q "service unreachable"; test -z "${GH_TOKEN:-}"'; ec=$?; rm -rf "$d"; exit $ec) && (bash -n bin/lib/component.sh && PLUGIN_ROOT=$PWD bash -c 'set -euo pipefail; source "${BU_ROOT}/lib/core.sh"; source bin/lib/component.sh; t=$(mktemp -d); printf "components:\n  - name: object\n    paths: [\".\"]\n    version_files: [package.json]\n" > "$t/ok.yaml"; printf "components:\n  - name: web\n    workspace: w\n    paths: [a]\n" > "$t/both.yaml"; printf "components:\n  - name: web\n    paths: [a]\n    colour: red\n" > "$t/unknown.yaml"; component_load "$t/ok.yaml"; test "$(component_names)" = object; test "$(component_field object version)" = yes; ! component_load "$t/both.yaml" 2>/dev/null; ! component_load "$t/unknown.yaml" 2>/dev/null; rm -rf "$t"') && (bash -n bin/lib/version.sh && PLUGIN_ROOT=$PWD bash -c 'set -euo pipefail; source "${BU_ROOT}/lib/core.sh"; source bin/lib/component.sh; source bin/lib/version.sh; t=$(mktemp -d); cd "$t"; git init -q r; cd r; git config user.name t; git config user.email t@example.com; printf "{\"name\":\"o\",\"version\":\"1.0.0\"}\n" > package.json; printf "components:\n  - name: object\n    paths: [\".\"]\n    version_files: [package.json]\n" > components.yaml; git add .; git commit -q -m "chore: init"; git tag v1.0.0; echo a > a; git add a; git commit -q -m "feat: add a"; component_load components.yaml; test "$(version_next object)" = 1.1.0; test "$(version_next object rc)" = 1.1.0-rc.1; version_write object 1.1.0; grep -q "\"version\": \"1.1.0\"\|\"version\":\"1.1.0\"" package.json; test "$(version_tag object 1.1.0)" = v1.1.0; cd /; rm -rf "$t"') && (bash -n bin/lib/check.sh && PLUGIN_ROOT=$PWD bash -c 'set -euo pipefail; source "${BU_ROOT}/lib/core.sh"; source bin/lib/component.sh; source bin/lib/check.sh; t=$(mktemp -d); cd "$t"; git init -q r; cd r; git config user.name t; git config user.email t@example.com; printf "components:\n  - name: object\n    paths: [\".\"]\n    checks: [\"true\"]\n" > components.yaml; git add .; git commit -q -m "chore: init"; git tag v0.0.1; echo a > a; git add a; git commit -q -m "feat: add a"; component_load components.yaml; check_minimum object; echo b > b; git add b; git commit -q -m "not conventional"; ! check_minimum object 2>/dev/null; cd /; rm -rf "$t"') && (bash tests/git-release/dry-run.sh && bash ${BU_ROOT}/app lint modules) && (bash tests/git-promote/ff.sh && bash ${BU_ROOT}/app lint modules) && (f=.agentic-os/project/concepts/git-workflow-plugin/notes/pilot-release.md; test -s $f && grep -q '^## Repository' $f && grep -q '^## Result' $f && ! grep -qiE 'TBD|TODO' $f) && (npm ci --ignore-scripts >/dev/null 2>&1 && bash -n bin/modules/lint/node.sh && test -x bin/modules/lint/node.sh && bash ${BU_ROOT}/app lint modules && bash ${BU_ROOT}/app lint node full && t=$(mktemp -d) && printf 'var unused = 1\nif (unused == 2) { debugger }\n' > "$t/bad.mjs" && ! bash ${BU_ROOT}/app lint node specific "$t/bad.mjs" >/dev/null 2>&1; ec=$?; rm -rf "$t"; exit $ec)

## P4 Daily loop and guards (outlined)

Build start, commit and pr, the aggregate status check, rules-sync with the STAGE switch, the pre-push guard and the adapted workflow-status and branch-cleanup (roadmap milestone m4-daily-loop).

## P5 Monorepo (outlined)

Release each component on its own, split components marked split: yes with splitsh-lite, baseline the existing child repositories and apply --latest=false in multi-component repositories (roadmap milestone m5-monorepo).

## P6 Retire the old approach (outlined)

Remove the old CI except status-checks.yml, replace the classic protection code, and correct the stale project context wording (roadmap milestone m6-retire-old).

## Review focus

- T1.1: The done check counts report rows; it does not test that a row marked confirmed rests on a run against the sandbox. A claim about the behaviour of an App token must not be confirmed from documentation alone.
- T1.1: The sandbox repository may use settings (repository ruleset against organisation ruleset, plan tier) that differ from the consuming projects, so a confirmed row can fail in production. Each row should name the settings it was run under.
- T1.2: The done check counts rows only. The splitsh-lite linkage and libgit2 rows must be checked against the release binary version the image will pin, not against whichever version is newest.
- T1.3: The note must stay a contract and a decision record. Server code or deployment scripts of the token service would exceed what the concept settled, and no done check catches that.
- T1.4: The declaration must hold a single source for a component's paths (the workspace graph or an explicit list per component), and its single-repository case (one component at the root) must be written out. No done check reads the note for either.
- T2.2: The verify run proves that the pinned versions are in the image, but not that a wrong checksum fails the build. The build must stop on a mismatch, with no fallback download and no latest tag, and nothing from the old Dockerfile (Node, the Gemini and Claude installs, gh-wf, libgit2-dev, openssh-client) may remain.
- T2.3: No done check reads the argument lists of the calls. The installation token must reach the container by environment variable name, never in an argument, a log line or a file, and there must be no fallback to a host binary (concept decision D35).
- T2.4: The verify run cannot show that the machine is clean in every respect, only that git-cliff and splitsh-lite are absent from the host path and that the image runs. The developer states which machine it was run on.

## Review reports

- order: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin/plan-review-order.md
- registrations: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin/plan-review-registrations.md
- assumed-code: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin/plan-review-assumed-code.md
- precedent: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin/plan-review-precedent.md
- proofs: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin/plan-review-proofs.md

## Decisions

- D1 [decided] Which phases the plan details -> P1 is detailed; P2 to P6 are outlined, one per later milestone of the roadmap (P2 to P6 depend on the checks of P1. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D2 [decided] Where the check reports and design notes are written -> .agentic-os/project/concepts/git-workflow-plugin/notes/ (It lies inside the project scope trigger and next to the concept's raw input. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D3 [decided] How the GitHub App behaviours are checked -> A test GitHub App installed on a sandbox repository that the developer registers before T1.1 starts (The behaviours cannot be checked by reading documentation alone. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D4 [decided] How the token service authenticates a developer (CONCEPT-git-workflow-plugin D48, left to the plan) -> An existing gh login checked against organisation membership (The white paper's recommendation in row Q-G; it needs no new credential on a developer machine. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D5 [decided] What happens when the token service is down -> Fail closed: no App write happens while the service is down (Concept decision D30 leaves no human write path, and a manual token would reopen the personal-token problem. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D6 [decided] Format of the component declaration (CONCEPT-git-workflow-plugin D44, left to the plan) -> One structured file at the repository root with explicit lists for checks and version files, and no kind field (The white paper's recommendation in row Q-O. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D7 [decided] Whether JS components take their paths from the workspace graph (CONCEPT-git-workflow-plugin D46) -> Yes: the workspace graph and turbo --affected; other components list paths in the declaration (The white paper's recommendation in row Q-R. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D8 [decided] How pre-releases are handled (CONCEPT-git-workflow-plugin D47) -> Settled after T1.2 reports white paper line 390 (the git-cliff pre-release counter); T1.4 writes the answer into its note (The white paper's row Q-H says verify first, and T1.4 depends on T1.2. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D9 [superseded] How the plan's tasks are carried out -> inline (No task is bash or hook code, T1.1 needs the developer's own account, and T1.3 and T1.4 are dialogue. Developer answer, recommended option.; developer, 2026-11-03, plan-only) superseded by D23
- D10 [superseded] Whether T1.3 also settles where the token service runs and who holds the App key -> Yes: the token service note gets a Service hosting section naming the hosting and the key custody (The m1 gate says the token service is settled, and concept D6 says the App private key never reaches a developer machine. Developer answer, recommended option.; developer, 2026-11-03, durable) superseded by D15
- D11 [decided] Which task owns the white paper lines 411 and 654 -> T1.1 takes both lines; its report holds eleven rows (Both are GitHub latest-release behaviour under concept decision D56; the white paper marks 18 lines and no task owned these two. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D12 [decided] How the verify runs prove the notes -> The verify runs test content: the result column of each row, a named decision on refuted or changed rows of T1.1, the citation of L500 in the token service note and of L390 in the component declaration note, and no TBD, TODO or open question (A structure-only check passed empty or TBD notes. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D13 [decided] How the sandbox prerequisite of plan decision D3 is enforced -> A developer-owned task T1.0 writes sandbox.md; T1.1 depends on it (No task or dependency encoded the order. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D14 [decided] What the P1 gate proves -> The gate runs the verify.run of every P1 task (T1.0 to T1.4), each in its own subshell, joined with && (A test -s over the notes passed one-row notes and could not see a missing line or the sandbox note; the milestone gate m1-foundations needs the coverage and content proofs. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D15 [superseded] Where the token service runs (corrects D10, which had the note name the hosting) -> The platform is not chosen now: the note fixes the requirements the platform must meet (HTTPS endpoint, private key only in the service's secret store, no logging of tokens, rejection of non-members) and the platform is chosen before the release core phase (P3) is detailed (The developer chose to name the hosting later and gave no infrastructure to name. Consequence: the milestone gate m1-foundations is met for the contract, the authentication, the fallback and the key custody, not for the hosting platform.; developer, 2026-11-03, durable) superseded by D25
- D16 [decided] Who holds the production App private key -> The key exists only in the service's secret store, with no backup; an org owner generates it and rotates it by generating a new key and deleting the old one; a lost key is replaced, not recovered (Fewest copies, least exposure; GitHub lets an org owner generate a new key at any time and keep several keys active. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D17 [decided] The contract between the CLI and the token service -> The CLI sends the developer's gh login token, the repository and the permission set the command needs; the service checks the login and the organisation membership and returns an installation token narrowed to that repository and permission set, valid for the one hour GitHub fixes; the CLI keeps it in memory, hands it to the tool container as an environment variable by name, never writes it to disk and drops it after the command (The one-hour lifetime and the narrowing by repository and permissions were measured on 2026-11-03; a membership check works with the developer's repo-scoped login. Developer answer, approved as stated.; developer, 2026-11-03, durable)
- D18 [decided] How pre-releases are handled in detail (the answer D8 deferred to the result of T1.2) -> A pre-release has a release commit like a final release, made by `release <component> --pre <channel>`; the version files carry the pre-release version; the CLI composes the first -<channel>.1 from the base version and git-cliff counts the following ones (git-cliff 2.8.0 has no --pre and cannot start a pre-release line, but increments an existing one (row L390); one mechanism keeps the tag equal to package.json. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D19 [decided] Name and syntax of the component declaration file -> components.yaml at the repository root, YAML, read on the host with yq (Matches the white paper's sketch in Appendix B and decision D6 (a structured file at the repository root); the tool image needs no parser. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D20 [decided] How modules call the tool image (the plan part of concept decision D55) -> An ephemeral container per call (docker run --rm), with the mounts of the call; no long-running container (Measured on 2026-11-03: about 0.5 s per ephemeral call against about 0.1 s per docker exec. Mounts of a long-running container are fixed at its start, so a worktree outside them breaks, and the plugin would have to manage that container and replace it when the image changes. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D21 [decided] Which platforms the tool image supports -> linux/amd64 only, pinned in the compose file; an arm64 host runs it through Docker's emulation, which is not measured (The only splitsh-lite release (v1.0.1) has a linux amd64 binary and none for arm64 (row L595 of verify-tools.md), and the arm64 download of the Dockerfile returns 404. Developer answer, recommended option.; developer, 2026-11-03, durable)
- D22 [superseded] Where the pinned versions, the base image digest and the checksums live -> In the plugin settings bin/config/env.defaults with keys PLUGIN_EDOTZ_GIT_WORKFLOW_*, overridable by the .env file in the project root; the compose file and the library function read the same values (Developer answer in free text: use the plugin config and its corresponding overwrite .env in the project root. Read as the existing file env.defaults, not as a new file with a leading dot; to be confirmed with the approval of this amendment.; developer, 2026-11-03, durable) superseded by D24
- D23 [decided] Who carries out the tasks of P2 (supersedes D9 for this plan) -> The bash tasks go to bash-author through /aos:bash-authoring with a review; the Dockerfile, the compose file and the pins are written inline; the clean machine check is the developer's. The mode header of the plan becomes subagents. (The framework prescribes the authoring pipeline for bash code; the tasks of P1 were research notes, which fitted inline. Developer answer, recommended option.; developer, 2026-11-03, plan-only)
- D24 [superseded] Where the pinned versions, the base image digest and the checksums live, after D22 -> In .env.defaults in the plugin root, with unprefixed keys (IMAGE_BASE, GH_VERSION and so on); a consuming project does not override them, and bin/config/env.defaults keeps only the settings a project may override through its .env (Developer correction on 2026-11-03: the pins are plugin internals read by the compose file and the library function, while the plugin config in bin/config is the overridable part. The framework loads only the file name env.defaults from bin/config, so that file keeps its name.; developer, 2026-11-03, durable) superseded by D33
- D25 [decided] Where the token service runs, after D15 deferred it -> As a Docker container on the developer's own machine, with the service code and its configuration (organisation, App ID, permission set of each command) in the image; the App's private key is a read-only file on the host, mounted into the container at run time and never part of an image, a repository or a log; the other requirements of the note stay (HTTPS endpoint, no token logging or storing, refusal of non-members, narrowed tokens only) (Developer answer on 2026-11-03: run it on this machine as a Docker container holding all needed information and configuration; for the key the developer chose the mounted secret, not the image. This machine is the one declared exception to the note's rule that the key is not on a developer machine; D16 holds otherwise (one copy, no backup, an organisation owner rotates it). Consequence under D5: while this machine or the container is down, nobody releases, and developers on other machines reach the service only through an endpoint this machine exposes, which is still to be settled.; developer, 2026-11-03, durable)
- D26 [decided] Who reaches the token service, which D25 left open -> Only this machine: the service listens on the local machine and is not exposed to other machines, no tunnel and no certificate; its purpose is to learn how it works and to be able to change it (Developer answer on 2026-11-03. It closes the open point of D25. Consequence: the release commands work on this machine only, and a developer on another machine cannot get a token (D5, fail closed). A shared or exposed endpoint is a later decision that supersedes this one.; developer, 2026-11-03, durable)
- D27 [superseded] In which language the token service is written -> Node with Octokit (@octokit/auth-app): the App JWT, the installation token request and its narrowing come from the maintained library; a small HTTP server in its own image under token-service/ that holds code and configuration, the key mounted as a host file (D25); the tool image stays free of Node (concept D34) (Developer chose the recommended option on 2026-11-03: the security-critical parts are not hand-rolled.; developer, 2026-11-03, durable) superseded by D30
- D28 [decided] Whether the release notes carry an LLM summary in P3 (concept D49) -> No: the release commit, the CHANGELOG and the GitHub Release body come from git-cliff alone and are deterministic; a summary through provider_run_prompt on the host (concept D18) is a later addition (Developer chose the recommended option on 2026-11-03: the m3 gate does not depend on an LLM.; developer, 2026-11-03, durable)
- D29 [decided] What the release does to the README -> It rewrites only the lines between the markers <!-- release:start --> and <!-- release:end --> (a version badge and a release link: releases/tag/<tag> of the component, in a single repository the same link form); the rest of the README stays the author's; a README without the markers is left untouched and the release says so (Developer chose the recommended option on 2026-11-03: no template and no generation, which the concept leaves out of scope (D20).; developer, 2026-11-03, durable)
- D30 [superseded] How the token service is laid out in the plugin, after D27 -> Node with Octokit as before (D27), but as a module command: bin/modules/git/token-service.mjs with the shebang #!/usr/bin/env node, registered in module.yaml as app git token-service with requires node; its dependency @octokit/auth-app in the package.json of the plugin root; its configuration in bin/config/token-service.json; its image and compose file in the .docker directory (.docker/token-service.Dockerfile, .docker/compose.token-service.yaml); its check in tests/token-service/check.sh; the key stays a mounted host file (D25) (Developer feedback on 2026-11-03: the modules may run Node through the shebang, a package.json belongs in the project directory and the Docker configuration in .docker. The dispatcher is polyglot: the interpreter comes from the shebang.; developer, 2026-11-03, durable) superseded by D32
- D31 [decided] Which linter the Node lint command runs -> Biome: the command app lint node of the plugin tier (bin/modules/lint/node.sh, added to the framework's lint domain) runs Biome over the Node files in the modes staged, changed, full and specific; Biome is an exactly pinned devDependency (@biomejs/biome 2.6.4) in the package.json of the plugin root with its configuration in biome.json at the root (Developer answer on 2026-11-03, recommended option: the old status-checks.yml already runs biome in the consuming projects, so one tool and one configuration. app lint all is a framework command and does not run the Node linter; it has to be called on its own.; developer, 2026-11-03, durable)
- D32 [superseded] How the images and compose services are laid out after D30 -> One central .docker/Dockerfile holds a stage per image (tool, token-service); one docker-compose.yaml in the plugin root builds both services with context . and dockerfile .docker/Dockerfile, a target per service and IMAGE_BASE as build arg on both; compose commands take --env-file .env.defaults, which replaces the default .env so that a project .env cannot change the pins (D24). The root Dockerfile, .docker/compose.yaml, .docker/compose.token-service.yaml and .docker/token-service.Dockerfile are removed; the rest of D30 (module command, root package.json, bin/config/token-service.json, tests/token-service/check.sh, key as mounted host file) stands. (Developer instruction on 2026-11-04: set a central Dockerfile in .docker and integrate the root docker-compose.yaml for tools and token service.; developer, 2026-11-04, durable) superseded by D33
- D33 [decided] Whether a .env can override the pins of .env.defaults, after D24 and D32 -> The pins live in .env.defaults of the plugin root as the fallback; the .env of the plugin root, when it exists, overrides a pin key by key; the .env of a consuming project and the process environment do not change them, and bin/config/env.defaults keeps the settings a project may override. Compose commands take --env-file .env.defaults followed by --env-file .env when that exists, and tool_image_ensure merges the same two files and hashes the Dockerfile with the resolved pins. The layout of D32 stands: one central .docker/Dockerfile with the stages tool and token-service, one root docker-compose.yaml. (Developer correction on 2026-11-04: .env.defaults is the fallback of .env, not a fixed set; the developer chose the .env of the plugin root as the overriding file.; developer, 2026-11-04, durable)
- D34 [decided] Which composer.json does version_write refuse -> version_write refuses a listed composer.json only when it has no version key and aligns it when it has one, as the component declaration note says; the brief wording refused when listed is read that way (The author of the version library followed the note; the developer approved on 2026-11-04; developer, 2026-11-04, durable)
- D35 [decided] What version_next returns when nothing is new -> version_next prints nothing and returns status 1 when no commit of the component is newer than its latest tag; a caller reads it with if v=$(version_next ...), because a plain assignment ends under the ERR trap (A commit outside every component bumps none; developer approved on 2026-11-04; developer, 2026-11-04, durable)
- D36 [decided] How often a command calls token_fetch -> A command calls token_fetch once per run; token_drop unsets GH_TOKEN even when it was exported, and the installation token is not exported, so a second call in the same shell finds no developer login when that login was an exported GH_TOKEN; a command that needs two permission sets runs two processes (The token service contract is one request per command run; developer approved on 2026-11-04; developer, 2026-11-04, durable)

## Revisions

- 2026-11-03 Cover white paper lines 411 and 654 in T1.1, make the verify runs test content, add the developer task T1.0 for the sandbox and record D11 to D13 (affects T1.0, T1.1, T1.2, T1.3, T1.4, D11, D12, D13) -- Review findings of the lenses proofs, order and assumed-code, settled with the developer in round 1 (claude)
- 2026-11-03 Replace the grep -vq test in the T1.1 verify run by a grep -c test, which gives the same result on every grep (affects T1.1, D12) -- The first form returned the wrong exit code under the grep wrapper of this shell, so a refuted row without a named decision would have passed; D12 is unchanged (claude)
- 2026-11-03 The P1 gate chains the verify runs of T1.0 to T1.4 instead of testing four files for size, and decision D14 records it (affects P1, D14) -- Review finding of the lens proofs: the gate could not see the coverage gap or the missing sandbox note, settled with the developer in round 2 (claude)
- 2026-11-03 T1.3 defers the hosting platform and fixes its requirements; D10 is superseded by D15; D16 records the key custody and D17 the contract (affects T1.3, D10, D15, D16, D17) -- The developer chose to name the hosting platform later, so the plan records the deferral instead of leaving the done wording unmet (claude)
- 2026-11-03 Record D18 (pre-release rule) and D19 (components.yaml) as the developer's answers for T1.4 (affects T1.4, D18, D19) -- The developer answered the two open points of the component declaration; D8 had deferred the pre-release rule to the T1.2 result (claude)
- 2026-11-03 Detail P2 Tool image with the tasks T2.1 to T2.4, record D20 to D23, supersede D9 by D23 and set the mode header to subagents (affects P2, T2.1, T2.2, T2.3, T2.4, D9, D20, D21, D22, D23) -- The developer asked to detail the tool image now that the T1.2 findings are known; D20 to D23 are the developer's answers on the call model, the platforms, the place of the pins and the owners (claude)
- 2026-11-03 The pins move from bin/config/env.defaults to .env.defaults in the plugin root, not overridable by a project (affects T2.1, T2.2, T2.3, P2) -- Developer correction: bin/config holds only the settings a project may override (developer)
- 2026-11-03 The pins in .env.defaults lose the PLUGIN_EDOTZ_GIT_WORKFLOW_ prefix (affects T2.1, T2.2, T2.3, P2, D24) -- Developer correction: the root .env.defaults is not a framework plugin file, so the plugin prefix does not apply (developer)
- 2026-11-03 The T2.1 verify and the phase gate read the unprefixed pin keys (affects T2.1, P2) -- The key loop built the prefix from a variable, so the first rewrite missed it (developer)
- 2026-11-03 The token service runs as a Docker container on the developer's machine, the key a mounted host file (affects D15, D16) -- Developer chose the platform D15 deferred, and the mounted secret for the key (developer)
- 2026-11-03 The token service is reachable from this machine only (affects D25) -- Developer closed the reach question of D25 (developer)
- 2026-11-03 P3 Release core detailed with eight tasks T3.1 to T3.8 and a gate; decisions D27 to D29 added (affects P3, T3.1, T3.2, T3.3, T3.4, T3.5, T3.6, T3.7, T3.8, D27, D28, D29) -- Developer approved the P3 breakdown after choosing the token service language, git-cliff-only release notes and marker-line README updates (developer)
- 2026-11-03 The token service becomes the module command app git token-service with the package in the root package.json and the Docker files in .docker (affects T3.1, T3.2, T3.8, P3, D27, D30) -- Developer feedback: Node modules through the shebang, package.json in the project directory, Docker configuration in .docker (developer)
- 2026-11-03 T3.9 added: the Node lint command app lint node with Biome; decision D31 (affects P3, T3.9, D31) -- Developer asked for a Node linter under bin/modules/lint and chose Biome (developer)
- 2026-11-03 T3.9 waits for T3.4 and takes target change, because it edits package.json and token-service.mjs (affects T3.9) -- lint plans: T3.9 and T3.4 shared a group and T3.4's verify names package.json; the entry check refuses target new over existing paths (developer)
- 2026-11-04 Merge the tool and token service images into one .docker/Dockerfile and one root docker-compose.yaml; gates of P2 and P3 and the T3.8 input follow, D30 is superseded by D32 (affects P2, P3, T3.8, D30, D32) -- Developer instruction on 2026-11-04 to set a central Dockerfile in .docker and integrate the root docker-compose.yaml; done tasks keep their record (developer)
- 2026-11-04 Pins in .env.defaults become the fallback of the .env of the plugin root: D33 supersedes D24 and D32 (affects D24, D32, D33) -- Developer correction on 2026-11-04: .env.defaults is the fallback of .env; the plugin-root .env overrides pins key by key (developer)
- 2026-11-04 T3.2 verify and the P3 gate run under env -u GH_TOKEN with a stub gh; decisions D34 (composer.json), D35 (version_next status 1) and D36 (one token_fetch per run) recorded (affects T3.2, P3, D34, D35, D36) -- The T3.2 check failed in a shell with an exported GH_TOKEN; the authors of T3.4 and T3.2 chose three behaviours the briefs leave open; developer approved on 2026-11-04 (developer)
- 2026-11-04 T3.6 carries D7 and D15, T3.7 carries D16; D8, D14, D17, D19, D31 and D54 are dismissed with the phase that carries them (affects T3.6, T3.7, P4, P6) -- lint chain named nine durable decisions that no task carries or dismisses; claude chose carry or dismissal by phase, for the developer to revise (claude)
