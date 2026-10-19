---
paths:
  - ".agentic-os/commands/**"
---

# .agentic-os/commands

The project's own commands: registration, provider config and blueprints, authored through the pipeline.

## Purpose and conventions
- A command is registered in `commands.yaml` with `name`, `type` and `description` only; provider fields live in `commands.<provider>.yaml`; `commands.json` only enables and disables.
- The body is assembled from blueprints under `blueprints/<placeholder>/<name>.md`, one file per placeholder, body only.

## Environment
- `bash bin/app compile commands` builds the artifacts; `bash bin/app lint yaml changed` checks the registration (the default mode lints only staged files) and `jq empty .agentic-os/commands/commands.json` or `lint json changed` checks the manifest.

## Constraints
- Compiled artifacts are build output: never hand-edited.
