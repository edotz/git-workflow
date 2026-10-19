---
paths:
  - ".agentic-os/skills/**"
---

# .agentic-os/skills

The project's own skills: registration, provider config and blueprints, authored through the pipeline.

## Purpose and conventions
- A skill is registered in `skills.yaml` with `name`, `type` and `description` only; the description states trigger conditions, never a workflow summary. Provider fields (such as the activation paths) live in `skills.<provider>.yaml`; `skills.json` only enables and disables.
- The body is assembled from blueprints under `blueprints/<placeholder>/<name>.md`, one file per placeholder, body only; the placeholders come from the template of the skill's `type`.

## Environment
- `bash bin/app templates skills` lists the types and the shape of each; `bash bin/app compile skills` builds the artifacts; `bash bin/app lint yaml changed` checks the registration (the default mode lints only staged files) and `jq empty .agentic-os/skills/skills.json` or `lint json changed` checks the manifest.

## Constraints
- Compiled artifacts are build output: never hand-edited.
