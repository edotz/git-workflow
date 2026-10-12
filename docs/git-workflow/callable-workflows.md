# Git Workflow — Callable Workflows & Pinned Actions (Monorepo)

## Callable Workflows (`edotz/git-workflow`)

| File | Purpose | Key inputs |
|---|---|---|
| `_callable-post-release.yml` | Generate README → stash → checkout MAIN_BRANCH → copy release files → restore README → backport PR + auto-merge | `release_branch`, `backport_to`, `backport_files`, `release_type`, `project_type`, `version`, `force_readme` |
| `_callable-release-please.yml` | Run `googleapis/release-please-action@v4` on `RELEASE_BRANCH` | `release_branch`, `release_type`, `package_name` |
| `_callable-status-checks.yml` | Parametrised linting — each check enabled by a boolean flag | `enable_commit_lint`, `enable_biome`, `enable_php_cs_fixer`, `enable_shellcheck` |
| `_callable-merge-split-repo.yml` | Matrix push of packages from monorepo to childrepos via `edotz/monorepo-split-action@v1` | `packages` (JSON array), `branch`, `organization` |
| `_callable-sync-to-monorepo.yml` | Generate README on childrepo + create sync PR in monorepo | `monorepo_repo`, `monorepo_package`, `release_branch`, `backport_files`, `release_type`, `project_type` |

All callable workflows require the `NPM_AUTH_TOKEN` secret (PAT for `ohoeft`).

## Monorepo Automated Sequence

```
promote PR merges into RELEASE_BRANCH
  └─ merge-split-repo-<RELEASE_BRANCH>.yml fires
       └─ Dynamic matrix: scans PACKAGES_DIR for subdirs with .github/workflow.env
            └─ Pushes each qualifying package → its childrepo (parallel)
                 └─ release-pipeline.yml fires in childrepo
                      └─ release-please → release PR → auto-merge → tag
                           └─ release-publish.yml fires (node packages only)
                           └─ sync-to-monorepo.yml fires
                                └─ Copies release files → monorepo PR → auto-merge
```

## Pinned Action Versions

All consuming repos must align to these versions.

| Action | Pinned version |
|---|---|
| `actions/checkout` | **v4** |
| `googleapis/release-please-action` | v4 |
| `wagoid/commitlint-github-action` | v6 |
| `biomejs/setup-biome` | v2 |
| `peter-evans/create-pull-request` | v7 |
| `ludeeus/action-shellcheck` | 2.0.0 |
| `shivammathur/setup-php` | v2 |
| `edotz/generate-readme-action` | 1.x |
| `edotz/monorepo-split-action` | 1.x |

## Childrepo Branch Protection

Childrepos have NO status checks — quality is guaranteed upstream in the monorepo.

| Branch | PR required | Status checks | `enforce_admins` | `bypass` | `restrictions` |
|---|---|---|---|---|---|
| `*` | no | none | false | none | none |
| `master` | no | none | false | `ohoeft` | `ohoeft` only |
| `RELEASE_BRANCH` | no | none | false | `ohoeft` | `ohoeft` only |
| Each `LEGACY_BRANCHES` | no | none | false | `ohoeft` | `ohoeft` only |

`bypass_pull_request_allowances: ohoeft` is required — the split workflow pushes directly.
`enforce_admins: false` is required for the bypass to function.
