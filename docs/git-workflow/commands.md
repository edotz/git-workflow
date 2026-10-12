# Git Workflow — Slash Commands & Bash Commands

## Slash Commands

| Command | Purpose | `sclaude` | `wsclaude` |
|---|---|---|---|
| `/git:start` | Create `feat/fix/chore` branch from `MAIN_BRANCH` | Required | Not needed |
| `/git:commit` | Generate conventional commit from staged changes only | ✓ | ✓ |
| `/git:pr` | Open PR for current branch with auto-merge enabled | ✓ | ✓ |
| `/git:merge` | Merge current branch into target (dev bypass — skips PR) | ✓ | ✓ |
| `/git:release` | Promote `MAIN_BRANCH` → `RELEASE_BRANCH` | ✓ | ✓ |
| `/git:status` | Show workflow state and next-action recommendation | ✓ | ✓ |
| `/git:setup-github` | Generate and apply GitHub infrastructure from `workflow.env` | ✓ | ✓ |
| `/git:setup-workflow` | Pre-flight health check — required files, config, generated file drift | ✓ | ✓ |
| `/git:worktree` | List active worktrees with session status | ✓ | ✓ |
| `/git:branch-cleanup` | Clean up merged branches and stale worktrees | ✓ | ✓ |
| `/trigger:release` | **Dev only** — manually trigger `release-pipeline-<RELEASE_BRANCH>.yml` | ✓ | ✓ |
| `/trigger:backport` | **Dev only** — manually trigger `post-release-<RELEASE_BRANCH>.yml` | ✓ | ✓ |
| `/monitor:release` | Check current release pipeline run status | ✓ | ✓ |
| `/monitor:action` | Check current generate-readme-action dist build run status | ✓ | ✓ |

### Notes

- `/git:release` and `/git:pr` targeting `RELEASE_BRANCH` are identical operations. `/git:release` is preferred — intent is explicit.
- `/trigger:*` commands are blocked when `STAGE=production` — they exit early and point to the automatic workflow run.
- `/git:start` is only needed in `sclaude`. In `wsclaude` the worktree IS the branch.
- `/git:commit` operates only on staged changes — never runs `git add`.
- In development, `/trigger:release` can be called with `skip_release_please=true` to run only post-release steps without bumping the version.
- `/trigger:backport` prompts for the version and optionally forces README regeneration (`force_readme=true`).

## Underlying Bash Commands

| Bash command | Invoked by |
|---|---|
| `bash bin/app git workflow-setup --apply` | `/git:setup-github` |
| `bash bin/app git workflow-setup --check` | `/git:setup-workflow` |
| `bash bin/app git workflow-setup validate` | ad-hoc config validation |
| `bash bin/app git run-status [--repo owner/name] [--limit n]` | `/monitor:release`, `/monitor:action` |
