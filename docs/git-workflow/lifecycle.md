# Git Workflow — Developer Lifecycle (Dev vs. Production)

## Session Start

| | `sclaude` | `wsclaude` |
|---|---|---|
| **Flow** | env picker → `bin/app claude init` → `claude` in current repo | env picker → worktree picker → new or existing worktree → `exec claude --worktree` |
| **Branch isolation** | None — on whatever branch the repo currently is | Full — you ARE the branch (git worktree checkout) |
| **`/git:start`** | Required — creates `feat/fix/chore` branch from `MAIN_BRANCH` | Not applicable |
| **When to use** | Quick work in the main repo | All feature/fix work (preferred) |

Both commands prompt `p=production / d=development`:
- `d` → uses `~/workspace/edotz.claude-code/bin` (live dev framework)
- `p` (default) → uses `~/.claude/bin` (deployed stable framework)

## Developer Lifecycle Table

| Step | Command | Development (`STAGE=development`) | Production (`STAGE=production`) |
|---|---|---|---|
| Create branch | `/git:start` *(sclaude only)* | Branch from `MAIN_BRANCH` | Same |
| Commit | `/git:commit` | Conventional commit from staged changes | Same |
| Open PR | `/git:pr` | PR to `MAIN_BRANCH`, auto-merge enabled | Same — status checks enforced |
| Merge to MAIN | auto, or `/git:merge` to bypass | `enforce_admins: false` — direct merge by `ohoeft` allowed | `enforce_admins: true` — status checks must pass |
| Promote to RELEASE | `/git:release` | Stage-guard bypassed — promote PR merges freely | Stage-guard active |
| Trigger release pipeline | `/trigger:release` | Manual only — does not auto-fire in dev | Auto-fires on merge into `RELEASE_BRANCH` |
| Post-release backport | auto; `/trigger:backport` if it fails | Manual via `gh workflow run post-release-*.yml` | Auto-fires after release PR merges |

## Automated Release Train Sequence

```
promote PR merges into RELEASE_BRANCH
  └─ release-pipeline-<RELEASE_BRANCH>.yml fires
       └─ release-please runs → release PR created/updated
            └─ release PR auto-merges → git tag created
                 └─ post-release-<RELEASE_BRANCH>.yml fires
                      ├─ Checkout RELEASE_BRANCH → resolve version
                      ├─ edotz/generate-readme-action@v1 generates README.md
                      ├─ Stash README → checkout MAIN_BRANCH
                      ├─ Copy release files (package.json, CHANGELOG.md, ...)
                      ├─ Restore README
                      └─ Create backport PR → auto-merge → MAIN_BRANCH up to date
```

## Conventional Commit → Version Bump

| Commit type | Bump |
|---|---|
| `feat:` | minor |
| `fix:`, `perf:`, `revert:` | patch |
| `feat!:` / `BREAKING CHANGE:` | major |
| `chore:`, `ci:`, `build:` | none |
| `docs:` | none (appears in CHANGELOG) |
