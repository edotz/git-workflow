# Playbook: the daily loop

Run every command as `bash ${BU_ROOT}/app git <command>`. Docker must run for the commands that use
the tool image (`start`, `commit`, `pr`, `release`, `promote`, `split`, `workflow-status`).

## Start

- Command: `start <type> <name>`.
- Type: one of `feat fix docs style refactor perf test build ci chore`.
- Name: lower case words joined by single hyphens.
- Read: the last line of the output is the new branch name; the checkout is on it, with no
  upstream.
- Carry-over: uncommitted changes of the working tree go along to the new branch.
- Stop on exit 1 (branch exists locally or on origin, or the local main branch differs from
  `origin/<main>`): run the hint the message prints, then start again.
- Stop on exit 2 (unknown type, invalid name, missing argument): correct the arguments.
- Stop on exit 4: Docker is not running.

## Commit

- Command: `commit --message "<type>(<scope>): <subject>" --yes <paths>`.
- Group: one commit per logical group of paths; name only the paths of that group.
- Stage: the command stages the named paths; files that were staged before stay staged and are not
  committed.
- Header: at most 100 characters, type from the list above, lower case scope, no full stop.
- Report: the line `commit — <sha>` and the subject; a warning about the footer is no refusal.
- Stop when the output says the message is refused: nothing was committed and the index is restored.
  Correct the message and run the command again.
- Without a terminal, leave out neither `--message` nor `--yes`: the confirmation reads standard
  input and declines with `commit: not confirmed, nothing was committed`.

## Check

- Command: `check [component]`.
- Read: one line per component, `ok` or `failed`, with the reason of the first failing step.
- Scope: the commit lint covers every commit since the latest tag of the component.
- Stop while a component is red: fix the cause, commit the fix, run `check` again.

## Pull request

- Dry run: `pr --dry-run` prints the branch, the title and the body; nothing is pushed.
- Title: the subject of the commit when the branch has one commit; otherwise the branch name read as
  `<type>: <name with spaces>`.
- Refusal: a title that commitlint refuses, with the squash suffix ` (#9999)` appended, is refused
  before the push. Shorten the title by renaming the branch or squashing the commits into one.
- Refusal: the main branch, a red minimum check and a branch with no commit of its own are refused.
- Apply: `pr` pushes with the developer's `gh` login and prints the pull request URL.
- Ask the developer before the apply: it pushes a branch and opens a pull request.

## After the merge

- The developer squash-merges on GitHub; no command merges.
- Update the main branch with git: `git switch <main>` and `git pull --ff-only`.
- Delete merged branches with `branch-cleanup`: it asks on standard input, `--force` skips the
  question, `--dry-run` only reports. It keeps the checked-out branch, protected and legacy branches
  and a branch at the same commit as the main branch.

## Read the state

- `workflow-status` prints JSON: the unreleased commits, per component the latest release tag
  and the commits since it, the release branch position and the recent workflow runs.
- `workflow-setup validate` prints the two branch settings.
