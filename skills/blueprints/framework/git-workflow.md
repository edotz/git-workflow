### Branch settings of this session (Procedural)

<branch-settings>
[[push:bash ${BU_ROOT}/app git workflow-setup validate]]
</branch-settings>

- Read both values before a release or a promote.
- A `GIT_WORKFLOW_RELEASE_BRANCH` exported in the shell wins over the `.env` of the project.
- When both values are `master`, promote has nothing to do.

### The loop (Procedural)

Below, `app git` stands for `bash ${BU_ROOT}/app git`, the way every command is run.

1. `app git start <type> <name>`: branch `<type>/<name>`, no upstream.
2. `app git commit --message "<type>(<scope>): <subject>" --yes <paths>`: one
   logical group per commit. Without a terminal `--message` and `--yes` are required, because
   the confirmation reads standard input.
3. `app git check`: commit lint since the latest tag plus the declared checks.
4. `app git pr --dry-run`, then `app git pr`: pushes with the developer's `gh`
   login and opens the pull request.
5. The developer squash-merges on GitHub. No command merges, and the title becomes the commit.
6. `app git release --dry-run`, then `--apply`: release commit, tag and GitHub
   Release as the App.
7. `app git promote <tag> --dry-run`, then `--apply`: the release branch follows
   the tag.

Start Docker first: most commands run their tools in the plugin's tool image and stop with
`Command not found: docker` without it.

### Rules that always hold (Guardrail)

- Never `gh pr create --fill`.
- Never `--no-verify`.
- Never force push the main or the release branch.
- Never move or delete a remote tag by hand.
- Run the dry run before every `--apply` and `--confirm`.
- Apply only on the developer's go, after stating what the apply pushes, tags or publishes.
- Keep the process the same in the stage `development`.
- Keep tokens and keys out of files, commits and command lines.
- Keep the pull request title short: it becomes the squash subject, GitHub appends ` (#N)`,
  and `app git pr` refuses a title that no longer fits the header limit.

### Which command for which job (Criteria)

| Job | Command |
|---|---|
| Delete merged branches (asks on standard input, `--force` skips) | `branch-cleanup` |
| Read the state of branches, tags and runs | `workflow-status` |
| Install the hook shims | `shims` |
| Create or update the branch rulesets | `rules-sync` |
| Publish a component to its child repository | `split <component>` |

All of them run as `app git <command>`; release and promote are in the loop.

### Before a release or a promote (Criteria)

- A release needs a `feat`, `fix`, `perf` or breaking commit after the latest stable tag of a
  component. A baseline tag on `HEAD` is not a release, and no empty commit makes one.
- Promote accepts only a tag whose commit is `chore(<component>): release <tag>`.
- `--confirm <owner/repo>` is for the baseline mode: only when the dry run says the release
  branch is not an ancestor of the release commit.
- There is no backport: a fix reaches the release branch by a pull request, a release on master
  and a promote, and every unreleased `feat`, `fix` or `perf` commit on master ships with it.
- A split pushes one child per apply, never moves a child tag at another commit, and needs
  `--confirm` when the child does not descend from the split.
