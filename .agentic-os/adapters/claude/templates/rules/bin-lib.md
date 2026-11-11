---
paths:
  - "bin/lib/**"
---

# Shell libraries

Plugin-local bash libraries sourced by the git modules through PLUGIN_ROOT: github.sh, worktree.sh and the release-flow libraries check.sh, component.sh, remote.sh, rules.sh, split.sh, token.sh, tool.sh and version.sh.

## Purpose and conventions
- github.sh (gh api wrappers) and worktree.sh (git worktree helpers) are plugin-local libraries; scripts source them as `${PLUGIN_ROOT}/bin/lib/<name>.sh` (product.md).
- The release-flow libraries: component.sh reads components.yaml, version.sh gives the next version, tag and version files of a component, check.sh runs the minimum check of a component, remote.sh gives the owner/name of a remote and the developer identity from the local git configuration, rules.sh builds the GitHub ruleset JSON of master, release and legacy from bin/config/rulesets.yaml (the stage from GIT_WORKFLOW_STAGE, the branches from GIT_WORKFLOW_RELEASE_BRANCH and GIT_WORKFLOW_LEGACY_BRANCHES), token.sh fetches the installation token from the token service, split.sh gives the head of the split of a component from its first path, and tool.sh runs every tool in the tool image.
- Each library has a source guard variable `BU_STATE_<NAME>` and resolves core.sh through `${BU_LIB:-${BASH_SOURCE[0]%/*}}`.
- Worktrees live in `<GIT_WORKFLOW_WORKTREE_DIR or $HOME/worktrees>/<repo-name>/<name with / as ->`; the repo name is the main worktree's directory name, the same inside a linked worktree. The base must be an absolute path (a leading `~` is expanded) and is read at call time.
- The shebang `#!/bin/bash` stays in this directory (developer's answer).

## Decisions
- The libraries stay plugin-local by design, not contributed to the framework lib (developer's answer).

## Environment
- Needs `git` on PATH; worktree.sh calls `require_command "git"` at load time. github.sh and token.sh need `gh`, token.sh also `curl`, tool.sh `docker`, component.sh `jq` 1.5+ and `yq` 4.0+.

## Constraints
- A change is done when shellcheck is clean (developer's answer).
- worktree_create requires the local base branch to equal `origin/<base>` unless origin cannot be resolved; it prints only the path on stdout, git's own output is discarded.
- rules_json takes its branch patterns from the environment; an unset or blank GIT_WORKFLOW_RELEASE_BRANCH or GIT_WORKFLOW_LEGACY_BRANCHES is a config failure (exit 3), and the App id stays APP_ID_PLACEHOLDER until rules-sync sets it.
- token.sh sets GH_TOKEN without exporting it and writes it to no file, log line or argument.
