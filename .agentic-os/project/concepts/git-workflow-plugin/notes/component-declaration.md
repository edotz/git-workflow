# Component declaration (PLAN-plugin T1.4)

Settles what the concept decisions D38 (versioning unit and tag), D44 (format), D46 (paths from the workspace graph) and D47 (pre-releases) leave to the plan. It rests on the plan decisions D6, D7, D8, D18 and D19 and on the rows of `verify-tools.md`. The declaration replaces `PACKAGES_DIR` and the `workflow.env` per package.

## Fields

The declaration is the file `components.yaml` at the repository root (decision D19), one top-level key `components` holding a list with at least one entry. There is no `kind` field and there are no defaults that depend on a kind (decision D6): every check and every version file is listed.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `name` | string, lower case letters, digits and hyphens, starting with a letter | required | Names the component in its tag, its release commit and its GitHub Release. Unique in the file. It is no commit scope rule: scopes stay free (white paper, 6.6), which settles the line in the white paper's field table that calls the name "the allowed commit scope". |
| `workspace` | string | none | The `name` of a package of the pnpm workspace, for a JavaScript component. Its paths come from the workspace graph (decision D7). |
| `paths` | list of directories relative to the repository root | none | The directories of a component that has no workspace package, including shared code it depends on. A change in any of them is a change of the component. |
| `version` | `yes` or `none` | `yes` | A versioned component is released on its own with its own tag. `none` means no tag, no release commit and no GitHub Release. |
| `version_files` | list of files relative to the repository root | empty | The files the release commit aligns. The writer is chosen by the file name: `package.json` and `composer.json` use the JSON writer, `ext_emconf.php` the pattern writer. A file name without a writer is a configuration error, not a skipped file. With an empty list the release commit holds only the CHANGELOG and the README. |
| `checks` | list of shell commands | empty | The project's own quick checks, run from the repository root by the aggregate check and by the minimum check of the release (decision D32). A non-zero exit fails the check. The plugin adds nothing for a kind: it supplies commit lint and the aggregate, the project supplies the commands. |
| `split` | `yes` or `no` | `no` | `yes` only for a component that needs its own repository. |
| `owner` | string | required when `split` is `yes` | The owner of the child repository. |
| `repo` | string | required when `split` is `yes` | The name of the child repository. |
| `host` | string | `github.com` | The host of the child repository. |

Rules the declaration is checked against, before any command runs:

- Exactly one of `workspace` and `paths` is given. A component with both, or with neither, is refused: this keeps one source of a component's paths.
- An unknown field is refused.
- `owner`, `repo` and `host` are refused unless `split` is `yes`. `split: yes` needs `version: yes`, because the child receives the component's tags, and it is refused in a single repository (nothing to split from).
- `version: none` needs an empty `version_files`.
- Paths of two components may overlap, because shared code is meant to count for both; a commit that touches two components counts for both.
- `version_files` of the kinds seen in real projects: `package.json` aligns the `version` key. `composer.json` is listed only by a project that keeps a `version` key (row L237: Composer warns against the field and reads the tag, 52 of 80 real files do without it), and the writer refuses a listed `composer.json` that has none. `ext_emconf.php` is aligned by rewriting its one `'version' =>` line (row L239: one such line in each of 97 real files, the rewrite changes exactly one line in each). `pnpm-lock.yaml` is never listed: a version change leaves it unchanged (row L786).
- After writing, the command reads every version file back and fails when it does not hold the version it wrote (white paper, 6.3).

Example, from `edotz.hh-web` (white paper, Appendix B):

```yaml
components:
  - name: web
    workspace: hh-website
    version_files: [apps/web/package.json]
    checks: ["turbo run lint check-types build --affected"]
  - name: typo3
    paths: [apps/typo3-hub]
  - name: infra
    paths: [infra]
    version: none
    checks: ["terraform fmt -check", "terraform validate"]
```

## Path resolution

A component's paths are computed at each run and never stored.

- **`paths`:** the listed directories are used as written. `.` stands for the whole repository and is allowed only for the one component of a single repository.
- **`workspace`:** the paths are the directory of the named package plus the directories of every workspace package it depends on, directly or through others. The command asks pnpm on the host: `pnpm list -r --depth -1 --json --filter "<package>..."` prints the package and its workspace dependencies with their directories (pnpm 10.11.1, the version `edotz.hh-web` pins). The result is converted to repository-relative directories. A workspace component needs pnpm on the host; without it the command stops with a configuration error. The tool image carries no pnpm (decision D34).
- **Evidence:** for `hh-website` of `edotz.hh-web` the closure is `apps/web`, `packages/ui`, `packages/biome-config`, `packages/tailwind-config` and `packages/typescript-config`. `packages/api-client` is not in it: `apps/web/package.json` declares only the four workspace dependencies `@repo/ui`, `@repo/biome-config`, `@repo/tailwind-config` and `@repo/typescript-config`. The white paper's component table (B.2) lists `@repo/api-client` among the dependencies of `web`, which the real graph does not support; a hand-written `paths` list would have carried that error, the graph does not.
- **Bump:** the next version of a component comes from git-cliff with a tag pattern that matches only that component's tags and one `--include-path '<dir>/**'` per resolved directory. Observed with git-cliff 2.8.0 on a repository with a component `web` and shared code `ui`: with only `web/**` included, a `feat` in `ui/` after the last tag gives no new version (`web/v1.0.1` stays); with `web/**` and `ui/**` included the same commit gives `web/v1.1.0`. The printed version carries the tag prefix.
- **Release commit directory:** the CHANGELOG and the README of a component live in its home directory, which is the directory of its workspace package or the first entry of its `paths`. The release commit touches only the `version_files`, the CHANGELOG and the README of that component.
- **Checks:** `turbo --affected` is for the project's `checks` commands. It plays no part in the bump, which reads paths.
- **A commit outside every component:** it belongs to no component and bumps none.

## Pre-releases

Decision D18: a pre-release has a release commit like a final release, the CLI starts the pre-release line and git-cliff counts it. The rule rests on row L390 of `verify-tools.md`. git-cliff 2.8.0 has no `--pre` option, and `--bump` took `patch` and `minor` (`major` was not run) and rejected `rc` and a full version, so it cannot start a pre-release line. It does increment a line that exists: after the tag `v1.1.0-rc.1` a fix gives `v1.1.0-rc.2`. Found while writing this note: it increments the counter even when the commits ask for a larger version. After `web/v1.1.0-rc.1` a breaking commit gives `web/v1.1.0-rc.2` when all tags are matched, and `web/v2.0.0` when the pattern matches stable tags only.

- **Command:** `release <component> --pre <channel>` makes a pre-release, `release <component>` without `--pre` makes a final release. The channel is lower case letters, for example `alpha`, `beta` or `rc`. The counter is an integer from 1.
- **Tag and version:** `<component>/vX.Y.Z-<channel>.N`, and in a single repository `vX.Y.Z-<channel>.N`. The version files carry `X.Y.Z-<channel>.N`, so the tag always matches `package.json`.
- **Base:** the base version `X.Y.Z` is what git-cliff returns with the tag pattern that matches stable tags only (`^<prefix>v[0-9]+\.[0-9]+\.[0-9]+$`) and the component's include paths. A pre-release tag never moves the base. Observed: with the tags `web/v1.0.1` and `web/v1.1.0-rc.1` and a later fix, the stable-only pattern gives `web/v1.1.0`.
- **Final release:** the version is the base. A final release after pre-releases needs no other step, and it is `X.Y.Z` even when the last pre-release was `X.Y.Z-rc.3`.
- **Pre-release, line exists:** when the latest tag of the component is `<base>-<channel>.N` with the same base and the same channel, the version is what git-cliff returns with the pattern that matches all tags of the component (`^<prefix>v`), which is `-<channel>.N+1`. The CLI checks that the result has exactly that shape and stops with both values when it does not.
- **Pre-release, line starts:** in every other case the CLI composes `<base>-<channel>.1`. This covers the first pre-release after a stable tag, a new channel on the same base, and a base that changed since the last pre-release because larger commits arrived, as in the breaking commit above, where the base is `2.0.0` and the version `2.0.0-rc.1`.
- **GitHub Release:** created with `--prerelease`. A pre-release is never the latest release (row L411), so decision D56 needs nothing more for it.
- **`ext_emconf.php`:** the writer refuses a pre-release version. Only plain `X.Y.Z` values occur in the 97 real files and TYPO3's reading of a pre-release string was not run (row L239), so a component that lists `ext_emconf.php` makes final releases only.
- **A component with `version: none`:** has no pre-releases.

## Single repository

A single repository is the same model with one component at the root (decision D38).

```yaml
components:
  - name: object
    paths: ["."]
    version_files: [package.json]
```

- **Tag:** `vX.Y.Z` without a prefix, and `vX.Y.Z-<channel>.N` for a pre-release. The tag pattern of the bump is `^v`.
- **Release commit:** `chore(<name>): release vX.Y.Z`, touching the version files, the CHANGELOG and the README at the root.
- **Paths:** `["."]`, which makes every commit a change of the component. A component with `workspace` is allowed as well, for a single package workspace.
- **Refused:** `split: yes`.
- **Prefix:** with one component the prefix is dropped, with two or more it is required.
- **Becoming a monorepo:** when a second component is added, all tags take the prefix `<component>/`. The existing component continues from its latest unprefixed tag `vX.Y.Z`: if it has no prefixed tag yet, the CLI reads that tag as the start of its version line. The old tags stay and are never moved or deleted.
- **Latest release:** a repository with one component keeps the normal latest release; `--latest=false` applies only from two components on (decision D56, row L654).
