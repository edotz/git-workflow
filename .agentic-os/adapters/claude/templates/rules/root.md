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
- The node-slim variant (FROM node:22-bookworm-slim, Dockerfile:99-126) is the intended one. The Ubuntu variant (Dockerfile:1-63) and the duplicated Alpine builder stages are leftovers to remove (developer's answer).
- The container runs as the node user; the Dockerfile has no USER and a root PATH yet and has to follow this (developer's answer).
- The entrypoint is the framework `app`; the `COPY bin/gh-wf` and ENTRYPOINT gh-wf lines are stale (developer's answer).
- Tool binaries as pinned release downloads and both LLM CLIs (Gemini CLI via npm, Claude Code via install script) are not decided; they came with the draft (developer's answer).

## Environment
- Base node:22-bookworm-slim, WORKDIR /workspace; git-cliff v2.8.0 and splitsh-lite v1.0.1 are pinned in the download URLs (Dockerfile:9-16).

## Constraints
- All developers use identical tool versions through the container (developer's answer).
- Node major version 22, base image pinned by tag (Dockerfile:99).
