# Migration of edotz/typo3-cms for PLAN-plugin T6.3

`edotz/typo3-cms` moved from release-please and its workflows to the git-workflow plugin on 2026-11-10 and 2026-11-11. The production App `git-workflow-app` made every change on GitHub that is not a pull request; the developer merged the pull requests. No key or token was written to a file.

## Repository

- Pull request #72 (squash merge `831fdff`): `components.yaml` with one component `typo3-cms` (path `.`, version files `composer.json` and `ext_emconf.php`), `status-checks.yml` that runs the checks of `components.yaml` after a `setup-php` step with php-cs-fixer, and the removal of `release-please-config.json`, `.release-please-manifest.json`, `release-please.yml`, `backport.yml`, `commit-lint.yml` and `php-cs-fixer.yml`.
- Pull request #73 (squash merge `eb238e5`): the obsolete `.github/branch-protection.yaml` removed.
- Pull request #74 (squash merge `06f238c`): the project tier `.agentic-os/` with `project.yaml` (plugins `edotz.git-workflow` and `edotz.aos-typo3`, linter `php-cs` through `app php cs --dry-run`), and the check line of `components.yaml`.
- Baseline: the old `v2.0.x` tags sit only on the branch `2.x`, so master got new baseline tags: `v2.0.5` on master before the migration and `v2.0.6` on `06f238c` after it. Both are lightweight tags.
- Rulesets of the production stage: `master`, `release` (branch `release`) and `legacy` (`1.x`, `2.x`), created with `rules-sync --apply`. The classic protection of master and of the old branch patterns was removed by the developer, because classic wildcard rules block the deletion of branches; the obsolete branches are deleted. `1.x` and `2.x` keep their classic protection with the two old required checks until the ruleset takes over.
- The pre-push guard: the shims of the clone were in place (`app git shims --check`: `pre-commit`, `commit-msg` and `pre-push` current), so the minimum check runs before every push.

## Result

- Dry run of the release: green after the baseline tag `v2.0.6`, with the one pending step "v2.0.6 is HEAD: apply makes sure the tag is pushed and the GitHub Release exists". No commit since `v2.0.5` is a `feat` or a `fix`, so nothing was bumped.
- Apply with `--draft`: "push — master and v2.0.6" (already up to date) and "GitHub Release — v2.0.6 created", a draft; `v1.0.14` stays the latest published release.
- Promote: `app git promote v2.0.6 --dry-run` refused: "v2.0.6 is not a release tag, its commit reads 'chore/agentic os migration (#74)'". A promote follows a release commit by design, so the branch `release` does not exist yet; the first real release of typo3-cms creates it.
- The minimum check runs the check line on the host and in CI: `if command -v php-cs-fixer ...; then php-cs-fixer fix ...; else bash "${BU_ROOT:?}/app" php cs --dry-run; fi`. The runner has php-cs-fixer from `setup-php`, the developer machine has the tool image of `edotz.aos-typo3`.

## Defects the migration found

- A pull request opened with `gh pr create --fill` took its title from the branch name; the squash merge put `chore/agentic os migration (#74)` on master, and the commit lint of the release stopped on it. A published commit cannot be rewritten, so the baseline tag `v2.0.6` moved the lint range past it. Nothing lints a pull request title before the merge: an amend of the plan lints it in `pr.sh` and in the status-checks job.
- A check line that calls the plugin by absolute path fails on the runner, because the same `checks` run in CI and locally.
- The shell of the session exports `GIT_WORKFLOW_*`, `PROJECT_ROOT` and `AOS_PLUGIN_TIERS` of this repository over the `.env` of the project that is migrated; every command of the release ran with those unset.
- `git promote` has no path for a baseline tag on a commit that is not a release commit; a repository whose first tag after the migration is such a baseline has no `release` branch until its first release.

## Branch roles

Settled with the developer on 2026-11-11 (D79, D80): master is the development branch, `2.x` is the release branch and `1.x` the legacy line. Both old lines were diverged from master (`1.x` ahead 58 and behind 95, `2.x` ahead 24 and behind 12) and still carried release-please, commit-lint and php-cs-fixer workflows and the classic protection with the two old required checks.

- Settings: `GIT_WORKFLOW_RELEASE_BRANCH=2.x` and `GIT_WORKFLOW_LEGACY_BRANCHES=1.x`, given as environment overrides for the run of `rules-sync`, because the shell of the session exports its own values over the `.env`; the two lines still have to be written into the `.env` of typo3-cms by the developer.
- Rulesets: `rules-sync --dry-run` listed master, release and legacy as updates and named the classic protection of `2.x` and `1.x` with its two required checks; `--apply` moved the ruleset `release` to `refs/heads/2.x` and `legacy` to `refs/heads/1.x`, master unchanged.
- Freeze tag: `v1.x-legacy-freeze` existed only in the local clone and points at `5e7404b` of 2025-11-18, 85 commits behind the head of `1.x`, so it is no freeze of the head; I pushed it as it was ("new tag") before I saw that. The freeze of the head before the cleanup is the new tag `legacy/1.x-freeze` at `9240db9` (pushed, `gh api` answers `9240db9c`); `v1.x-legacy-freeze` stays as it is.
- Cleanup of the legacy line: pull request #75 (squash merge `b60479e`, title `ci: remove the old release workflows from the frozen legacy line (#75)`, linted before it was opened) removed `commit-lint.yml`, `php-cs-fixer.yml`, `release-please.yml`, `release-please-config.json`, `.release-please-manifest.json` and `.github/branch-protection.yaml` from `1.x`; the tree of `1.x` holds none of them.
- Classic protection: the pull request could only merge once the required checks of the classic protection no longer applied, because it removes the workflows that produce them; the developer authorised the removal and it was done with the API for `1.x` and `2.x` before the merge (`Branch not protected` for both). The legacy ruleset covered `1.x` already, so the branch was never unprotected. D80 put the removal after the cleanup; the order had to be the other one.
- Baseline of `2.x`: it keeps its old content and its old workflows until the first real release of typo3-cms. The one-time move to the release commit (tag `legacy/pre-promote`, force push with a lease) needs the baseline mode of `git promote` (D81, T6.9).
