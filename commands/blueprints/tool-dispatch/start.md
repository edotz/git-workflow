`$ARGUMENTS` is what the developer typed after the slash command.

When it holds a type and a name, run this one command and report its output verbatim:

```bash
bash ${BU_ROOT}/app git start $ARGUMENTS
```

Otherwise settle the missing part with the developer, then run the same command with the type and the name:

1. Take one typed word that is a commit type (the types of `commitlint.config.mjs`, listed in `START_TYPES` of `bin/modules/git/start.sh`) as the type, and one typed word that is not a type as the name.
2. Without a type, ask the developer for it: one question with two to four options, the type that fits the conversation first, then `feat`, `fix`, `chore` and `docs` up to four in all. A free-text answer names any other type of the list.
3. Without a name, ask the developer for it: one question with two or three options, each lower case words joined by single hyphens, two to four words, taken from the conversation. A free-text answer is the name the developer types; write it in that form. When the conversation gives nothing to propose, ask for a short description in plain words instead and turn it into the name.
4. Run `bash ${BU_ROOT}/app git start <type> <name>` and report its output verbatim.

The report ends the operation: take no further action after it.
