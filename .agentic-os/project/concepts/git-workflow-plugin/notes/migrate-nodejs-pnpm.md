# Move of edotz/nodejs-project from yarn to pnpm for PLAN-plugin T6.4

`edotz/nodejs-project`, the monorepo of ten npm packages under the scope `@edotz`, moved its workspace from yarn to pnpm on 2026-11-11, before the move to the git-workflow plugin (T6.6), because the `workspace:` components of the plugin call the package manager of the host and the tool image has no yarn setup.

## Repository

- Pull request #18, `build: move the workspace from yarn to pnpm`, squash merge `0d56d76`, merged 2026-11-11 12:12 UTC: 14 files, +6200 -951 lines, most of it the new pnpm lock file.
- Removed: `.yarnrc.yml` and `.yarn/releases/yarn-4.6.0.cjs`. Added: `pnpm-lock.yaml` and `pnpm-workspace.yaml`. Changed: `.npmrc`, the root `package.json` (`packageManager` is `pnpm@10.11.1`) and the `package.json` of the packages.
- `.npmrc` holds `shamefully-hoist=true` (hoist), so the packages resolve each other and their tools from the root `node_modules` as they did under yarn.
- The scripts that chain commands with `npm-run-all` run it with `--npm-path npm` (recorded in the migration state of the 2026-11-11 session; the reason is not rechecked here).
- pnpm 10 is the version of the host (the clone ran `corepack pnpm@10.11.1`).

## Why it matters for the plugin

- Every component of `components.yaml` carries a `workspace` field with its package name (`@edotz/data-handler` and so on); the check of a component runs through pnpm with that name, so a wrong package manager makes the check of every component red.
- The tool image cannot run git in a linked worktree and calls pnpm on the host: the clone for the split has to be a real clone with pnpm 10 on `PATH`.

## Result

- In a real clone at `721da35` with pnpm 10.11.1, `pnpm install --frozen-lockfile` answers "Lockfile is up to date" for all 11 workspace projects (the root and the ten packages) and exits 0, so the lock file and `pnpm-workspace.yaml` agree with every `package.json`.
- Nothing of yarn is left in the tree of master: no `.yarnrc.yml`, no `yarn.lock`, no `.yarn/releases`; a local working copy may still hold an ignored `.yarn` directory, which git does not track.
- The commit type of the move is `build`, so the move changes no component release on its own.
