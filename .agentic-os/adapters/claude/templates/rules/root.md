---
paths:
  - "Dockerfile"
---

# Container image

Container image of the git-workflow tools: node-slim base, pinned git-cliff and splitsh-lite, running as the node user, identical tool versions for all developers.

## Purpose and conventions
- The Dockerfile is a standing part of the project and builds the git-workflow tool image; it is untracked and does not build yet (developer's answer, git status).
- The image name and file name in 260903-git-workflow.md (git-workflow-suite:latest, Dockerfile.git-workflow) are outdated; the names are to be renamed.

## Decisions
- The node-slim variant (FROM node:22-bookworm-slim, Dockerfile:99-126) is the starting point. The Ubuntu variant (Dockerfile:1-63) and the duplicated Alpine builder stages are leftovers to remove (developer's answer). The image carries only git, gh, git-cliff and splitsh-lite, so it needs no Node and the plan settles the base image (concept).
- The container runs as the node user; the Dockerfile has no USER and a root PATH yet and has to follow this (developer's answer).
- The image has no entrypoint: `app` runs on the host and modules call the tools through docker (concept). The `COPY bin/gh-wf` and ENTRYPOINT gh-wf lines are stale.
- The image carries no LLM CLI (concept): the Gemini CLI and Claude Code installs of the Dockerfile are leftovers to remove, and the pinned release downloads get a checksum check.
- The image is defined with docker compose and a `.docker` config directory (concept); neither exists yet.

## Environment
- Base today node:22-bookworm-slim, WORKDIR /workspace; git-cliff v2.8.0 and splitsh-lite v1.0.1 are pinned in the download URLs (Dockerfile:9-16).

## Constraints
- All developers use identical tool versions through the container (developer's answer).
- The base image is pinned by digest and each download by checksum (concept); the Dockerfile still pins Node 22 and the base by tag (Dockerfile:99).
