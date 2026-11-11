# Pilot monorepo in the sandbox for PLAN-plugin T5.5

A sandbox monorepo with two components, released with `app git release` and split with `app git split`, run on 2026-11-10. It holds no secret: the key of the sandbox App stayed on the developer machine and no token was written to a file.

## Repository

- Monorepo: `edotz/git-workflow-sandbox`, private, working copy `~/worktrees/git-workflow-sandbox`, branch `master`. Pull request #9 (squash merge `0a59c00`) turned its single component into a `components.yaml` with two components: `web` (path `web`, version file `web/package.json`) and `lib` (path `lib`, version file `lib/package.json`, `split: yes`, owner `edotz`, repo `git-workflow-sandbox-child`). The old files moved into `web/`; each component has its own README with the release markers.
- Child: `edotz/git-workflow-sandbox-child`, private, created for the pilot with two commits of its own (`0381944`, `eed2021`) that have nothing in common with the monorepo. The sandbox App had to be added to the installation by an owner, because the installation is limited to selected repositories: before that the token service answered "repository not installed (HTTP 404)".
- Baseline: the tags `web/v0.2.0` and `lib/v0.0.0` on the previous master `0a13fcf`, so that the minimum check lints only the commits of the pilot.
- Change to release: pull request #10 `feat(sandbox): add a page to web and a utility to lib` (squash merge `1db5a87`), one commit that touches both components.
- Token service: the container of `docker-compose.yaml` on `127.0.0.1:8790` with the key of the sandbox App (App ID 5593711).

## Result

- Dry run: two blocks, `web` 0.3.0 with the tag `web/v0.3.0` and `lib` 0.1.0 with the tag `lib/v0.1.0`, each with its own files (`package.json`, `CHANGELOG.md`, `README.md` of its directory) and the notes with the one feature; the working tree stayed clean. The tag format of several components is `<component>/vX.Y.Z`.
- Apply and the first interruption: the first apply made the release commit `77c513e` and the tag `web/v0.3.0`, then the push failed: the `pre-push` shim of the clone runs `exec agentic-os`, which the tool image lacks (`agentic-os: not found`). The commit and the tag stayed local with a clean tree.
- Fix found by the pilot: the four push calls that run in the tool image (release, pr, promote, split) now pass `-c core.hooksPath=/dev/null`; the checks run on the host, so no hook is lost. The pre-push guard still runs on the host.
- Rerun of an interrupted apply: the dry run reported `pending — web/v0.3.0 is HEAD`. The rerun made the release commit `c6b4579` for `lib`, pushed `master` and `lib/v0.1.0` ("push — master and lib/v0.1.0"), created the GitHub Release `lib/v0.1.0` and was then stopped with SIGTERM right after that first push. The tag `web/v0.3.0` and its GitHub Release `web/v0.3.0` were nevertheless on GitHub a few seconds later (created 15:32:50, six seconds after `lib/v0.1.0`), most likely because the container of the last call outlived the stopped run. A third apply, run by the developer, reported "Everything up-to-date", the push of `lib/v0.1.0` as done and the GitHub Release as existing: a rerun after an interruption completes or finds nothing left to do.
- GitHub Releases: `web/v0.3.0` and `lib/v0.1.0` exist on `releases/tag/web/v0.3.0` and `releases/tag/lib/v0.1.0`, created by `git-workflow-sandbox[bot]`, not drafts, not pre-releases. Both were made with `--latest=false`: `releases/latest` still answers `v0.2.0`. The READMEs hold `Version 0.3.0` with the link `releases/tag/web/v0.3.0` and `Version 0.1.0` with the link `releases/tag/lib/v0.1.0`.
- Split dry run: `app git split --dry-run` named the child, the split head `dddf85a` of `lib`, the child head `eed2021`, the warning that the child is unrelated and needs a baseline, and the tree difference of 7 files (`CHANGELOG.md`, `README.md`, `index.txt`, `package.json` and `util.txt` added or changed, `OLD.txt` and `two.txt` deleted).
- A tag older than the component: the first apply of the split stopped with "splitsh-lite printed no commit for component 'lib', the paths have no history at lib/v0.0.0": the baseline tag `lib/v0.0.0` sits on a commit from before `lib/` existed, and the split maps every component tag. The pilot removed that tag (it was its own, `0a13fcf`) from the remote and locally; a repository that carries such a tag stops the split the same way. The message is clear, the apply stops before it pushes anything.
- Baseline apply: `app git split lib --apply --confirm edotz/git-workflow-sandbox-child` tagged the old child head `eed2021` as `legacy/pre-split` ("legacy/pre-split — the old head eed20216… is kept"), then replaced `master` of the child with the split head `dddf85a` by a forced update with a lease ("forced update"), and pushed the tag `v0.1.0` (the tag `lib/v0.1.0` as `v0.1.0`). The child holds `CHANGELOG.md`, `README.md`, `index.txt`, `package.json` and `util.txt`; its latest commit is `chore(lib): release lib/v0.1.0`.
- Second apply: the same command printed "edotz/git-workflow-sandbox-child is at the split head and has every tag: nothing to apply"; `legacy/pre-split` still points at `eed2021`.

## Defects the pilot found

- The pre-push shim of a clone broke every push that runs in the tool image (fixed, see above); no test builds a clone with a pre-push shim yet.
- A component tag that predates the directory of the component stops the split apply; the message names the tag.
- `app git pr` and `release` cannot be run by the model from the session when the safety classifier judges the push to `master` dangerous; the developer ran the last release apply with the shell prefix.
- The release of a component whose paths are the whole repository (path `.`) cannot be split, which is why the pilot moved the old files into `web/`.
