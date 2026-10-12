# Git Workflow — Related Repositories

## Repository Index

| Repo | Local path | GitHub | Role |
|---|---|---|---|
| `edotz.claude-code` | `~/workspace/edotz.claude-code` | `edotz/claude-code` | Framework: `bin/`, commands, skills, agents. Deployed to `~/.claude/`. |
| `edotz.git-workflow` | `~/workspace/edotz.git-workflow` | `edotz/git-workflow` | Reusable callable GitHub Actions workflows consumed by all project repos. |
| `edotz.generate-readme-action` | `~/workspace/edotz.generate-readme-action` | `edotz/generate-readme-action` | GitHub Action (`edotz/generate-readme-action@v1`) that generates `README.md` after every release. |

## edotz.claude-code Deployment Flow

```
~/workspace/edotz.claude-code/
  bin/           →  ~/.claude/bin/
  CLAUDE.md      →  ~/.claude/CLAUDE.md
  commands/      →  ~/.claude/commands/
  agents/        →  ~/.claude/agents/
  skills/        →  ~/.claude/skills/
```

Two environments at session start:
- `d` (development) → `~/workspace/edotz.claude-code/bin` — changes take effect immediately
- `p` (production, default) → `~/.claude/bin` — stable deployed copy

## edotz.generate-readme-action

**Action ref:** `edotz/generate-readme-action@v1` | **Current:** `v1.1.1` | **Release branch:** `1.x`

### Required files in every consuming repo

| File | Description |
|---|---|
| `docs/readme-config.json` | Project metadata: `projectName`, `projectDescription`, `author` (required), plus `features`, `license`, `repo`, `additionalResources` |
| `docs/README.md` | Content section injected as `{{{CONTENT}}}` in the template |

### Key inputs

| Input | Required | Description |
|---|---|---|
| `project-type` | Yes | `node` \| `php` \| `typo3` \| `boilerplate` \| `childrepo` \| `action` |
| `version` | Yes | Release version tag, e.g. `v1.2.3` |
| `force` | No | Force generation even if CHANGELOG unchanged |

### State detection

| Mode | Condition |
|---|---|
| `init` | `docs/README.md` does not exist |
| `update` | CHANGELOG has changed since last README write |
| `skipped` | No CHANGELOG diff — use `force: true` to override |
