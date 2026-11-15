# PLAN-plugin-02
Generated from PLAN-plugin-02.json, do not edit.

**Goal:** The token service container starts by itself when a Claude session opens through the module command app git token-start, and app git token-stop stops it, so release, promote, split and rules-sync find a service at the default address.

## Abstract

### Summary

Two new commands of the git module, token-start and token-stop, bring the token-service container of docker-compose.yaml up and stop it from the plugin root. A thin session-start hook calls token-start and stays silent. The hook is switched on in the hook registry, and the command reference, the architecture table and the token service manual describe the three. A test with a stubbed docker proves the start, the stop and the silent skips.

### Outcome

Opening a session on a machine with Docker running and the App ID and the key file set in the .env of the plugin root leaves the token-service container running on 127.0.0.1 port 8790. Without Docker or without those settings the session opens with no output and no error. app git token-stop stops the container by hand.

### Phases

- P1 Token service starts with the session: 5 tasks

### Cost

3 author runs (two bash-author runs for the commands and the test, one hook-author run for the hook), each followed by one review, plus one inline edit of the registry and three manuals.

### Decisions to confirm

none

### Open points

none

### Risks

The container holds an App key for as long as it runs and nothing stops it at session end; the developer stops it with token-stop. One App runs at a time and a running container of the other App is kept as it is. The write scopes of the tasks are not checked against the declared scopes before the write.

### Success

With the container removed and Docker running, a new session shows docker ps with token-service up and a POST to http://127.0.0.1:8790/token answers 401. app git token-stop leaves the container stopped. With Docker stopped the session opens with no message.

**Track:** deliberative  **Items:** B-3
**Status:** active  **Mode:** subagents

## P1 Token service starts with the session (detailed)

| Title | Task | Owner | Depends | Status |
|---|---|---|---|---|
| Write the module commands token-start and token-stop | T1.1 | bash-author | - | pending |
| Write the session-start hook that calls token-start | T1.2 | hook-author | T1.1 | pending |
| Write the test of the commands and the hook with a stubbed docker | T1.3 | bash-author | T1.1, T1.2 | pending |
| Enable the hook in the registry and describe the commands in the manuals | T1.4 | inline | T1.2 | pending |
| Prove the service live with the real container | T1.5 | inline | T1.3, T1.4 | pending |

**Write the module commands token-start and token-stop** (T1.1)
- Why: The privileged commands stop with service unreachable when no container runs, and today the developer types the compose lines by hand.
- Result: Two documented module commands that start and stop the token-service container.
- Done: app git token-start and app git token-stop are registered, shellcheck is clean and each answers --help; a reader sees that start refuses loudly on a missing precondition and that both call compose with the plugin root as project directory.
- Produces: git token-start app git token-start, no arguments, exit 0 started, non-zero with a reason when a precondition is missing
- Produces: git token-stop app git token-stop, no arguments, exit 0 stopped or not running

**Write the session-start hook that calls token-start** (T1.2)
- Why: A hook is what runs at session start, and a session must open the same for a developer without Docker or a key.
- Result: A silent hook that starts the service through the module command.
- Done: The file exists, is executable and parses; a reader sees that it calls token-start under timeout 20, discards its output and exits 0.
- Produces: session-start/token-service hook script bin/hooks/session-start/token-service, event session-start, no arguments
- Consumes: T1.1 git token-start app git token-start, no arguments, exit 0 started, non-zero with a reason when a precondition is missing

**Write the test of the commands and the hook with a stubbed docker** (T1.3)
- Why: The hook runs at every session start and must never block or leak; only a test shows that every refusal is loud for the command and silent for the hook.
- Result: A test of start, stop and the hook that needs no Docker.
- Done: bash tests/token-service/start-stop.sh prints one ok line per case and exits 0.
- Consumes: T1.1 git token-start app git token-start, no arguments, exit 0 started, non-zero with a reason when a precondition is missing
- Consumes: T1.2 session-start/token-service hook script bin/hooks/session-start/token-service, event session-start, no arguments

**Enable the hook in the registry and describe the commands in the manuals** (T1.4)
- Why: A hook script only runs once the registry enables it, and a reader of the manuals must learn that the service starts by itself and how to stop it.
- Result: The hook is on in this repository and the manuals describe the commands and the hook.
- Done: hooks.json lists session-start/token-service as enabled, app lint hooks and app lint snapshots exit 0 and each doc names the commands, the hook or the new scripts it was asked to carry.
- Consumes: T1.2 session-start/token-service hook script bin/hooks/session-start/token-service, event session-start, no arguments

**Prove the service live with the real container** (T1.5)
- Why: The stub of the tests proves the compose arguments, not that a container comes up and answers.
- Result: The token-service container was stopped and started again by the two commands and answers on port 8790.
- Done: The verify run exits 0: token-stop, token-start and a request without a token that gets 401.

Gate: bash tests/token-service/start-stop.sh && bash ${BU_ROOT}/app lint hooks

## Review focus

- T1.1: A container of the other App is already running: up -d keeps it, so the session gets the wrong App without any sign.
- T1.1: token-start and token-stop print no App ID, key path or key content in any branch, including a failing docker compose call.
- T1.2: The hook discards the output and the exit code of token-start and exits 0 on every path, and a slow docker compose up does not delay the opening of the session beyond a bounded time.

## Review reports

- order: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin-02/plan-review-order.md
- registrations: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin-02/plan-review-registrations.md
- assumed-code: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin-02/plan-review-assumed-code.md
- precedent: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin-02/plan-review-precedent.md
- proofs: /home/ohoeft/workspace/edotz.git-workflow/.claude/session/a24bcf21/reports/PLAN-plugin-02/plan-review-proofs.md

## Decisions

- D1 [decided] Which projects start the service: only the plugin repository, or every project that has the plugin? -> Every project with the plugin. (token_fetch in every consuming project asks 127.0.0.1:8790, and one container serves them all.; owner, 2026-11-15, durable)
- D2 [superseded] Where does the start logic live? -> In the hook script itself. (One docker compose call with skip checks and no second caller.; owner, 2026-11-15, plan-only) superseded by D5
- D3 [decided] Is the service stopped when the session ends? -> No stop, manual only; the manual stop is a module command (D5). (A stop at one session's end would cut off a second open session; the developer stops the container by hand today.; owner, 2026-11-15, durable)
- D4 [decided] Which App does the start use, and what if the container of the other App runs? -> The App of the .env of the plugin root; a running container is kept. (The start stays one simple call; a sandbox check already uses its own project name.; owner, 2026-11-15, plan-only)
- D5 [decided] Should the logic stay in the hook or go to module commands? -> The logic goes to module commands: one starts the service and one stops it; the hook only calls the start command. (The developer corrected the earlier answer: a command can be run by hand, tested alone and documented in the command listing.; owner, 2026-11-15, durable)
- D6 [decided] What are the names of the two module commands? -> token-start and token-stop. (They sit beside the existing token-service command, which runs the Node service itself.; owner, 2026-11-15, durable)
- D7 [decided] Start with or without --build? -> Without --build; compose builds only when the image is missing. (A build must not slow every session open; a pin change is a manual --build already documented.; owner, 2026-11-15, plan-only)
- D8 [decided] How do the command and the hook react to a missing Docker or setting? -> token-start refuses with a one-line reason and a non-zero exit; the hook discards the output and the exit code and exits 0. (A developer who runs the command by hand needs the reason; a session start must not fail or print for a developer without a key.; owner, 2026-11-15, durable)
- D9 [decided] Where does the compose call of the module commands run, and who is the container user? -> Compose runs with --project-directory at the plugin root and absolute env-file paths, so it works from any directory; TOKEN_SERVICE_UID and TOKEN_SERVICE_GID default to id -u and id -g. (Every consuming project runs the command from its own root, where docker-compose.yaml and the env files do not exist; the compose file takes the container user from the two variables.; owner, 2026-11-15, plan-only)
- D10 [decided] Does the registry task compile so the snapshot lint stays green? -> The registry task runs the compile after enabling the hook and its verify runs app lint snapshots. (A hook enabled without a compile leaves the stored hook inventory stale and a later lint all full fails.; owner, 2026-11-15, plan-only)
- D11 [decided] Is the time the hook can hold up a session opening bounded? -> The hook runs token-start under timeout 20 and exits 0 on a timeout; the test proves it with a slow stub. (A first start with a missing image must not hold every session open; the manual start finishes the build.; owner, 2026-11-15, durable)
- D12 [decided] Does a task prove the real container, not only the stub? -> A last inline task runs token-stop, token-start and a request without a token that must get 401. (The stub tests never start a container; the same gap was dismissed for the rules-sync task of the earlier plan.; owner, 2026-11-15, plan-only)
- D13 [decided] Does the registry task's verify prove each manual, not just one? -> One grep per file and name: token-start, token-stop and the hook name in the command reference and in the token service manual, the hook name in the architecture table. (grep -q over two files passes when only one matches.; owner, 2026-11-15, plan-only)
- D14 [decided] Which doc places does the registry task cover? -> The hook table, the module scripts table and the test suites table of architecture.md, the command reference, the token service manual and docs/troubleshooting.md, which joins the writes. (The two tables list what the plan adds and troubleshooting.md still tells the reader to start the service by hand.; owner, 2026-11-15, plan-only)
- D15 [decided] How does the test build its throwaway root? -> As the sibling tests do: an .agentic-os directory, the framework variables unset, PLUGIN_ROOT and PLUGIN_LIB exported, a case from another directory and a missing .env case that proves the temp root is the one read. (Decision D54 of the earlier plan and the sibling tests ff.sh and run.sh need exactly this setup.; owner, 2026-11-15, plan-only)
- D16 [decided] What does the test assert beyond the compose arguments? -> Sentinel App ID and key path in the temp .env must appear in no output, and the PATH holds only the stub and basic tools. (No case asserted the output content, and a case could reach the real docker.; owner, 2026-11-15, plan-only)

## Revisions

- 2026-11-15 Round 1 of the review: compose runs from the plugin root with the UID and GID set, the hook is bounded by timeout 20, the registry task compiles and lints snapshots, and a last task proves the real container (affects T1.1, T1.2, T1.3, T1.4, T1.5, D9, D10, D11, D12) -- The reviewers found a missing working directory, an unbounded hook, a stale snapshot after the enable and no live proof; the developer decided D9 to D12 (claude)
- 2026-11-15 Round 2 of the review: each doc is verified by its own grep, troubleshooting.md and the two architecture tables join the registry task, and the test builds its root like the sibling tests and asserts no secret in any output (affects T1.3, T1.4, D13, D14, D15, D16) -- The reviewers found a grep that passes on one of two files, doc places the brief missed and a test setup that could read the real .env; the developer decided D13 to D16 (claude)
