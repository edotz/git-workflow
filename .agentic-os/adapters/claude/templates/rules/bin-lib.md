---
paths:
  - "bin/lib/**"
---

# Shell libraries

Plugin-local bash libraries sourced by the git modules through PLUGIN_ROOT: github.sh, worktree.sh and the release-flow libraries check.sh, component.sh, token.sh, tool.sh and version.sh.

## Purpose and conventions
- github.sh (gh api wrappers) and worktree.sh (git worktree helpers) are plugin-local libraries; scripts source them as `${PLUGIN_ROOT}/bin/lib/<name>.sh` (product.md).
- The release-flow libraries: component.sh reads components.yaml, version.sh gives the next version, tag and version files of a component, check.sh runs the minimum check of a component, token.sh fetches the installation token from the token service, tool.sh runs every tool in the tool image.
- Each library has a source guard variable `BU_STATE_<NAME>` and resolves core.sh through `${BU_LIB:-${BASH_SOURCE[0]%/*}}`.
- Worktrees live in /home/ohoeft/worktrees; the `${PROVIDER_CONFIG_DIR}/worktrees` path in worktree.sh:22 is stale.
- The worktree.sh header requirement list (core.sh, json.sh) is stale from the move; it also needs paths.sh (worktree.sh:3, 12-13).
- The shebang `#!/bin/bash` stays in this directory (developer's answer).

## Decisions
- The libraries stay plugin-local by design, not contributed to the framework lib (developer's answer).

## Environment
- Needs `git` on PATH; worktree.sh calls `require_command "git"` at load time (worktree.sh:16). github.sh and token.sh need `gh`, token.sh also `curl`, tool.sh `docker`, component.sh `jq` 1.5+ and `yq` 4.0+.

## Constraints
- A change is done when shellcheck is clean (developer's answer).
- worktree_create requires the local base branch to equal `origin/<base>` unless origin cannot be resolved (worktree.sh:119-121).
- token.sh sets GH_TOKEN without exporting it and writes it to no file, log line or argument.
