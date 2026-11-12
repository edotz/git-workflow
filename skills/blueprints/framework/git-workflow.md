### Step 1 — Read the branch settings (Procedural)

<branch-settings>
[[push:bash ${BU_ROOT}/app git workflow-setup validate]]
</branch-settings>

- Read both values before a release or a promote.
- Trust these values over the shell: a `GIT_WORKFLOW_RELEASE_BRANCH` exported in the shell wins
  over the `.env` of the project.
- Resolve every plugin-relative path of the references against `${PLUGIN_ROOT}`.

### Step 2 — Run the loop (Procedural)

1. `bash ${BU_ROOT}/app git start <type> <name>`: stop on exit 1 or 2 and read the message.
2. `bash ${BU_ROOT}/app git commit --message "<type>(<scope>): <subject>" --yes <paths>`: commit
   one logical group of paths; stop when the message is refused.
3. `bash ${BU_ROOT}/app git check`: stop while a component is red.
4. `bash ${BU_ROOT}/app git pr --dry-run`, then `bash ${BU_ROOT}/app git pr`: ask the developer
   before the push; stop on a refused title.
5. Wait for the developer to squash-merge on GitHub; no command merges.
6. `bash ${BU_ROOT}/app git release --dry-run`, then `--apply`: stop at `Nothing to release`.
7. `bash ${BU_ROOT}/app git promote <tag> --dry-run`, then `--apply`: stop when the dry run names
   a baseline.

- Open [[ref:loop.md]] before step 1, and for `branch-cleanup` and `workflow-status`: what to
  read in each output, what to report, when to stop.
- Open [[ref:release-and-promote.md]] before step 6, a promote, a split, `rules-sync` or
  `shims`.
- Start Docker first: most commands stop with `Command not found: docker` without it.

### Step 3 — Keep the rules (Guardrail)

- Open a pull request with `bash ${BU_ROOT}/app git pr`; `gh pr create --fill` skips the title lint.
- Commit through `bash ${BU_ROOT}/app git commit`; `--no-verify` skips the gate.
- Move the release branch with `bash ${BU_ROOT}/app git promote <tag>`; a force push is out.
- Correct a wrong release with a new release; a remote tag stays where it is.
- Run the dry run before every `--apply` and `--confirm`.
- Apply on the developer's go, after stating what the apply pushes, tags or publishes.
- Treat the stage `development` like production: the process is the same.
- Keep the pull request title short: it becomes the squash subject with ` (#N)` appended.
- Keep tokens and keys out of files, commits and command lines.

### Step 4 — Check before a release, a promote or a split (Criteria)

- Release a component only when a `feat`, `fix`, `perf` or breaking commit follows its latest tag.
- Treat a baseline tag on `HEAD` as no release, and add no empty commit to make one.
- Promote a tag only when its commit is `chore(<component>): release <tag>`.
- Add `--confirm <owner/repo>` only when the dry run says the release branch is not an ancestor.
- Ship a fix to the release branch by pull request, release and promote; there is no backport.
- Split one child per apply, and add `--confirm` when the child does not descend from the split.
