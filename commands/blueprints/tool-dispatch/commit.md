`$ARGUMENTS` is what the developer typed after the slash command.

When it holds both `--message` and `--yes`, run this one command and report its output verbatim:

```bash
bash ${BU_ROOT}/app git commit $ARGUMENTS
```

Otherwise the command has no way to ask the developer anything in this session, so the message is written here, confirmed with the developer and passed in with `--message` and `--yes`. The words typed, if any, are the paths in scope.

1. List the changes with `bash ${BU_ROOT}/app git changes`. When nothing is listed, report that there is nothing to commit and stop.
2. Settle the scope:
   - Paths typed: the scope is those paths.
   - No paths typed and the index holds files but nothing else changed: the scope is the index.
   - No paths typed and more is changed: ask the developer whether to commit the files in the index only (offer that only when the index holds files), all changes as one commit, or split the changes into groups. A cancel stops here.
3. For all changes as one commit, the scope is every path of the list.
4. For a split, read the diffs and sort the paths into groups that each carry one purpose, no path in two groups. A group holds both paths of a rename.
5. Write one conventional message for each scope or group, from its diff.
6. Show the scopes with their paths and messages in one question and ask the developer to commit them as shown, or, for a split, to merge them into one commit, or to cancel. A free-text answer is the developer's change: apply it and ask the same question again. A cancel stops here.
7. Run each commit on its own, in the order shown, and stop at the first failure. Pass the message through a quoted heredoc, so no character of it is expanded, and quote every path in single quotes with a single quote inside it written as `'\''`:

```bash
bash ${BU_ROOT}/app git commit --message "$(cat <<'MSG'
<message>
MSG
)" --yes '<path>' '<path>'
```

   For the scope "the index" give no paths.
8. Report the output of every run verbatim.

The report ends the operation: take no further action after it.
