`$ARGUMENTS` is what the developer typed after the slash command.

When it is empty, or holds a stage together with `--apply`, run this one command and report its output verbatim:

```bash
bash ${BU_ROOT}/app git stage $ARGUMENTS
```

Otherwise switch in two steps, with a stage typed or asked for:

1. Without a stage in `$ARGUMENTS` (only `--apply` was typed), ask the developer for it: one question with the options `development` and `production`.
2. Run `bash ${BU_ROOT}/app git stage <stage>` and show its output verbatim. Stop when it exits with an error.
3. When the output holds a line that starts with `would switch`, ask the developer whether to switch now, with the options "Switch" and "Cancel", and name that the token service must run with the key of the App. Any other output ends the operation.
4. On "Switch", run `bash ${BU_ROOT}/app git stage <stage> --apply` and report its output verbatim. On "Cancel", stop.

The report ends the operation: take no further action after it.
