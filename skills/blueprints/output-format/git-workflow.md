When a step of the workflow is carried out or proposed, state one line per step:

```text
step: <command> | <dry run | apply | read> | <output line of the command or the refusal>
```

- Fill the last field with the output line of the command; a step without that line is reported
  as not done.
- Report a refusal with the exact message and the manual that explains it, then wait for the
  developer.
