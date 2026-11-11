# Migration of edotz/nodejs-project for PLAN-plugin T6.6

`edotz.nodejs-project`, the monorepo of ten npm packages, moved from the old release train to the git-workflow plugin on 2026-11-11. The production App `git-workflow-app` made every change on GitHub that is not a pull request; the developer merged the pull requests. No key or token was written to a file. The yarn to pnpm move (PR #18) is in `migrate-nodejs-pnpm.md`.

## Repository

- Roles (D79): `master` is the development branch and `1.x` the release branch; there is no legacy line, so the `.env` of nodejs-project needs `GIT_WORKFLOW_RELEASE_BRANCH=1.x` and no `GIT_WORKFLOW_LEGACY_BRANCHES`. Every command of the migration ran with environment overrides (`GIT_WORKFLOW_APP_ID=5694393`, `GIT_WORKFLOW_STAGE=production`, `GIT_WORKFLOW_MAIN_BRANCH=master`, `GIT_WORKFLOW_RELEASE_BRANCH=1.x`) because the shell of the session exports its own values.
- Pull request #19, `chore: git workflow migration`, squash merge `721da35`, merged 2026-11-11 12:31 UTC: 76 files, +134 -4376. At the root it added `components.yaml` with ten components, each with a `workspace` field (`@edotz/<name>`), and `.github/workflows/status-checks.yml`, and removed `commit-lint.yml`, `merge-split-repo.yml`, `.github/branch-protection.yaml` and `.github/README.md`. In each of the ten packages it removed `branch-protection.yaml`, `.github/CLAUDE.md`, `release-pipeline.yml`, `release-please-config.json`, `.release-please-manifest.json` and `sync-to-monorepo.yml`, and modified `release-publish.yml` (publish on a `v*` tag).
- Rulesets of the production stage: `master` (required check `check`) and `release` (`1.x`). The classic protection of `master` and `1.x` was removed only after both rulesets existed.
- Baseline tags: one lightweight tag per component on `721da35`, the squash commit that cleaned the package directories, so git-cliff finds no change after them: `data-handler/v1.0.3`, `dotenv-dotprop/v1.0.2`, `error-handler/v1.3.1`, `express-app/v1.3.4`, `json-validate/v1.0.1`, `logger/v1.0.1`, `react-app/v1.4.1`, `runtime/v1.1.2`, `transpiler/v1.0.7` and `utilities/v1.0.4`.

## Token set

The first split push to `data-handler` was rejected: the split head carries workflow files and the token had no `workflows` permission. Granting the permission to the App was not enough, because the token service narrows every token to the set of the command; T6.16 (D84) added the set `split` (contents and workflows write) to `bin/config/token-service.json`, and the image had to be rebuilt because it holds the config. Only the split apply asks for that set.

## Children

- `data-handler`: dry run said the child is unrelated to the split (8 files differ: the old workflows, `commitlint.config.mjs`, `package.json`). Apply with `--confirm edotz/data-handler`: the old head `a24c4c7` is kept as `legacy/pre-split`, `master` was replaced by the split head `efc22e3` with a lease ("forced update"), and the tag `v1.0.3`, which exists on the old commit `759f138`, was skipped with a warning and not moved (D83). Checked through the API afterwards.
- The other nine children (`dotenv-dotprop`, `error-handler`, `express-app`, `json-validate`, `logger`, `react-app`, `runtime`, `transpiler`, `utilities`): not baselined at the time of this note. A loop over them in the background was denied by the auto mode classifier; they follow one per run.

## Open

- The nine child baselines, then the child result lines in this note.
- `.npmrc` hoist and the `--npm-path npm` argument stay; a package that stops needing them is a later cleanup.
- The release branch `1.x` keeps its old content until the first real release; its one-time move needs `promote baseline` (D81).
- A `ci:` commit after a baseline tag that touches a package directory makes git-cliff propose a patch release; the amend (commit range instead of tag search) is open.
