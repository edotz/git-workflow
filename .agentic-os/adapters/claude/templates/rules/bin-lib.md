---
paths:
  - "bin/lib/**"
---

# Shell libraries

Plugin-local bash libraries (github.sh, worktree.sh) sourced by the git modules through PLUGIN_ROOT.

## Purpose and conventions
- github.sh (gh api wrappers) and worktree.sh (git worktree helpers) are plugin-local libraries; scripts source them as `${PLUGIN_ROOT}/bin/lib/<name>.sh` (product.md).
- Each library has a source guard variable and resolves core.sh through `${BU_LIB:-${BASH_SOURCE[0]%/*}}` (github.sh:7-11, worktree.sh:7-11).
- Worktrees live in /home/ohoeft/worktrees; the `${PROVIDER_CONFIG_DIR}/worktrees` path in worktree.sh:22 is stale.
- The worktree.sh header requirement list (core.sh, json.sh) is stale from the move; it also needs paths.sh (worktree.sh:3, 12-13).

## Decisions
- The libraries stay plugin-local by design, not contributed to the framework lib (developer's answer).
- The main branch comes from `.github/workflow.env` when a project declares it; env.defaults holds the defaults. worktree.sh:158-165 still hardcodes `master` and reads `MAIN_BRANCH=` only, and has to follow this.

## Environment
- Needs `gh` and `git` on PATH; worktree.sh calls `require_command "git"` at load time (worktree.sh:16).

## Constraints
- A change is done when shellcheck is clean (developer's answer).
- worktree_create requires the local base branch to equal `origin/<base>` unless origin cannot be resolved (worktree.sh:119-121).
