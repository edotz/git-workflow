# Git Workflow — Pre-flight Gate & Key Rules

## Pre-flight Gate

Run before any release promotion:

```bash
/git:setup-workflow
```

Checks automatically:
- `docs/readme-config.json` — exists, `projectName` / `projectDescription` / `author` non-empty
- `release-please-config.json` — `pull-request-title-pattern` contains `${version}`
- `.release-please-manifest.json` — `"."` version matches latest git tag
- No open release-please PRs on `RELEASE_BRANCH`
- Generated files not drifted from templates
- `edotz/generate-readme-action` `1.x` branch HEAD reachable and `dist/templates/<WS_PROJECT_TYPE>.md` present (skipped if `gh` unavailable or `WORKFLOW_TYPE=monorepo`)

Drift failures → fix with `/git:setup-github`.
Required-file failures → fix manually.

## Key Rules

- Never push directly to `MAIN_BRANCH`, `RELEASE_BRANCH`, or any legacy / childrepo branch
- Never edit generated artifacts — the next `/git:setup-github` will overwrite them
- Always enable auto-merge after opening a PR
- PRs always merge via merge commit (`--merge`) — never squash or rebase
  - Exception: sync-to-monorepo backport uses `--squash` (single `chore(backport):` commit)
- Squash/rebase disabled repo-wide — preserves individual CC commits verbatim so release-please correctly detects version bumps
- `chore:`, `ci:`, `build:` commits → no version bump
- `docs:` commits → appears in CHANGELOG, no version bump
- `feat:` → minor bump · `fix:` / `perf:` / `revert:` → patch bump · `feat!:` / `BREAKING CHANGE:` → major bump

## Status Check Key → GitHub Job Name Mapping

| Key | Job `name:` in callable workflow |
|---|---|
| `commit-lint` | `Validate Conventional Commits` |
| `biome` | `Biome Code Quality` |
| `php-cs-fixer` | `PHP-CS-Fixer` |
| `shellcheck` | `ShellCheck` |
| `eslint` | `ESLint Code Quality` |
