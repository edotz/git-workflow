---
paths:
  - ".agentic-os/agents/**"
---

# .agentic-os/agents

The project's own agents: registration, provider config and blueprints, authored through the pipeline.

## Purpose and conventions
- An agent is registered in `agents.yaml` with `name`, `type` and `description` only; provider fields (model, tools, skills, memory) live in `agents.<provider>.yaml`; `agents.json` only enables and disables.
- The body is assembled from blueprints under `blueprints/<placeholder>/<name>.md`, one file per placeholder, body only.

## Environment
- `bash bin/app compile agents` builds the artifacts; `bash bin/app lint yaml changed` checks the registration (the default mode lints only staged files) and `jq empty .agentic-os/agents/agents.json` or `lint json changed` checks the manifest.

## Constraints
- Compiled artifacts are build output: never hand-edited.
