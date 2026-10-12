# Git Workflow — `workflow.env` Variable Reference

Every consuming repo has a `.github/workflow.env` file. The framework reads this file to
generate all workflow artifacts via `bash bin/app git workflow-setup --apply`.

## Monorepo-level Variables (`.github/workflow.env`)

| Variable | Values | Description |
|---|---|---|
| `WORKFLOW_TYPE` | `single` \| `monorepo` | Determines which workflow set is generated |
| `REPO_OWNER` | e.g. `edotz` | GitHub organisation or user |
| `REPO_NAME` | e.g. `my-repo` | GitHub repository name |
| `MAIN_BRANCH` | e.g. `master` | Active development trunk |
| `RELEASE_BRANCH` | e.g. `1.x` | Release-please target; promote destination |
| `LEGACY_BRANCHES` | e.g. `0.x` (comma-separated, may be empty) | Legacy release branches that are their own trunk |
| `STAGE` | `development` \| `production` | Controls `enforce_admins` and stage-guard behaviour |
| `STATUS_CHECKS` | e.g. `"commit-lint,biome"` | Comma-separated check keys enabled on `MAIN_BRANCH` PRs |
| `RELEASE_TYPE` | `node` \| `php` \| `simple` | Drives release-please and default backport file list |
| `PROJECT_TYPE` | e.g. `action`, `node`, `php` | Passed to `edotz/generate-readme-action` as `project-type` |
| `PACKAGE_NAME` | e.g. `@edotz/my-pkg` | npm package name (node only) |
| `BACKPORT_FILES` | e.g. `package.json CHANGELOG.md` (space-separated) | Override default backport file list; leave empty to use RELEASE_TYPE defaults |

## Package-level Variables (`packages/<name>/.github/workflow.env`, monorepo only)

| Variable | Description |
|---|---|
| `REPO_NAME` | Childrepo name (e.g. `php-object`) |
| `RELEASE_TYPE` | `node` or `php` |
| `MONOREPO_REPO` | Backport destination (e.g. `edotz/php-project`) |
| `MONOREPO_PACKAGE` | Path within `PACKAGES_DIR` (e.g. `object`) |
| `RELEASE_BRANCH` | Inherited from monorepo `workflow.env` |
| `LEGACY_BRANCHES` | Inherited from monorepo `workflow.env` |

A package's presence of `.github/workflow.env` is the opt-in signal for splitting.
Packages without this file are never split to a childrepo.

## Default Backport Files by `RELEASE_TYPE`

| RELEASE_TYPE | Default backport files |
|---|---|
| `node` | `package.json .release-please-manifest.json CHANGELOG.md README.md` |
| `php` | `composer.json .release-please-manifest.json CHANGELOG.md README.md` |
| `simple` | `.release-please-manifest.json CHANGELOG.md README.md` |
