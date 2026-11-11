---
paths:
  - ".docker/**"
---

# Docker

Container images of the git-workflow plugin: the pinned tool image and the token service image, one Dockerfile with a stage per image, pins from .env.defaults and .env

## Purpose and conventions
- One Dockerfile holds three stages: `fetch` (downloads and verifies the tool binaries), `tool` (git, jq, git-cliff, splitsh-lite, gh; WORKDIR /workspace; no entrypoint) and `token-service` (the Node token service, port 8790, user node). Source: Dockerfile:3, 28, 42-50.
- The compose file at the project root builds each service from this Dockerfile with one target per service (tool, token-service). The pins come from .env.defaults and the plugin-root .env overrides them key by key. Source: docker-compose.yaml.
- Pins are unprefixed keys: IMAGE_BASE, IMAGE_PLATFORM, GIT_CLIFF_VERSION and SHA512, SPLITSH_VERSION and SHA256, GH_VERSION and SHA256. Source: .env.defaults.

## Decisions
- The tool stages take their base from IMAGE_BASE, the token-service stage pins node:22-bookworm-slim by digest in the Dockerfile. The developer wants both bases unified: the token-service digest should move to the pins like the others (developer's answer).

## Environment
- Build context is the project root: the token-service stage copies package.json, package-lock.json, the token service script and its config by relative path. Source: Dockerfile:44-47.
- Compose commands need the pins: `--env-file .env.defaults`, then `--env-file .env` when it exists. Source: .env.defaults header.

## Constraints
- The six fetch build args and GIT_APT_VERSION must be non-empty or the build fails (proven: Dockerfile:11-14, 32).
- Each downloaded archive must match its checksum, git-cliff by SHA512, splitsh-lite and gh by SHA256 (proven: Dockerfile:19, 22, 25).
- The fetch stage downloads linux amd64 binaries only (proven: Dockerfile:18, 21, 24).
- The token service installs production dependencies only, with install scripts off, and runs as the non-root node user (proven: Dockerfile:45, 48).
- The token-service base image is pinned by digest (proven: Dockerfile:42).
