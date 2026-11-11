# Sandbox for the checks of PLAN-plugin T1.1

The test setup the GitHub App checks run against. Written by T1.0, 2026-11-03. It holds no secret: the private key of the App stays on the developer machine.

## Repository

- Repository: `edotz/git-workflow-sandbox`, private, owned by the organisation `edotz`.
- Default branch: `master`.
- A minimal workflow `.github/workflows/check.yml` with one job named `check` gives the required status check a context to wait for.
- The repository is a sandbox and may be deleted after T1.1.

## App

- Name: `git-workflow-sandbox`, owned by `@edotz`, installable only on that account.
- App ID: 5593711.
- Installed on the repository `git-workflow-sandbox` only (the developer's confirmation; not read back through the API, because the token of this session lacks the organisation scope for it).
- Permissions, read back through the API: first Contents write, Pull requests write, Administration read, Metadata read. Later raised to Administration write and Packages write, accepted on the installation 2026-11-03 11:18 UTC (see verify-github.md, rows L500 and L467). Every other repository permission is "No access".
- Webhook inactive; no user authorization flow is used.
- Row L500 of the verify report decides whether Administration read-only is enough for ruleset sync.

## Settings

- Organisation plan: team.
- Ruleset level: repository ruleset `master-protection` (id 26442774), active on the default branch; no organisation ruleset applies. The consuming projects may use organisation rulesets, so a row of T1.1 that depends on the ruleset level must say so.
- Ruleset rules: deletion, non_fast_forward, pull_request with 0 required approvals, required_status_checks with the context `check`.
- Bypass actor: the App (Integration 5593711), bypass mode `always`.
- Merge settings: squash merge only (merge commit and rebase off), squash commit title from the PR title, squash commit message from the PR body, delete branch on merge on.
