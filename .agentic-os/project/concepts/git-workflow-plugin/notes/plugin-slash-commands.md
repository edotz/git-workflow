# Slash commands of a plugin: what the framework does

Date: 2026-11-04. Written for the developer to double-check in the agentic-os project (`/home/ohoeft/workspace/edotz.claude-code/bin`, called `bin/` below). Nothing here was run as a compile; each point says whether it was run or read.

## Why this was looked at

The git-workflow plugin ships its daily-loop commands as bash modules (`app git <command>`). The developer asked for slash commands (`/git:<command>`) that a consuming project gets with the plugin. The session `plugin` has the purpose `project`; the plugin commands belong to the deliverable tier, which for a plugin project is the plugin root. The question was whether this is a dead end: whether the plugin can provide slash commands at all, where they are registered, how the compile finds them, and whether the project itself, registered as a plugin, can use them.

PLAN-plugin was amended for this (T4.13, decisions D42 to D44); the findings below show that T4.13 as written rests on a point that does not hold (see Gap).

## Verified by running a command

| Fact | Command | Result |
|---|---|---|
| The project is already registered as a plugin | `app plugins list` | `edotz.git-workflow 0.1.0 modules,hooks`, root `.` |
| The plugin tier is in the chain of this project | `echo $AOS_TIER_CHAIN` | `project=… plugin:edotz.git-workflow=<repo> framework=… project-adapter=… provider=…` |
| The plugin modules resolve here | `app git list` | `release`, `promote`, `lint-commit`, `token-service` and others listed |
| `registration-dir` ignores a path argument | `app tiers registration-dir commands commands/foo.md` | same output as without the path |
| Purpose `project` registers in the project tier | `app tiers registration-dir commands` | `.agentic-os/commands/commands.yaml (purpose: project)` |
| Purpose `deliverable` registers in the plugin root | `AOS_PURPOSE=deliverable app tiers registration-dir commands` and `hooks` | `commands/commands.yaml`, `bin/hooks/hooks.yaml` |
| `hook-target` resolves the plugin tier from a path | `app tiers hook-target bin/hooks/commit-msg` | `tier plugin, root .` |
| The session purpose cannot be changed | `meta.json` of the session, `docs/configuration.md` | `purpose: project`; an existing session keeps its value and refuses a differing flag, except for an axis that is empty |

## Read in the code

1. **A plugin tier is scanned for registration when `provides` lists the surface.** `lib/capability.sh:164-187` (`capability_scan_dirs`) reads `<type>.yaml` from every directory of `tier_dirs`; `lib/tiers.sh` adds a plugin directory only when `plugin_provides` names the class (`_tier_plugin_has`). Entries carry `origin: plugin:<name>`; the project wins on a name collision.
2. **A plugin adds registration only.** `lib/capability.sh:114-128` (`capability_load_spec`) reads only `<type>.yaml` of a plugin tier, never `<type>.<provider>.yaml`; `lib/plugins.sh:172-178` prints a notice for such a file ("overrides belong to the project").
3. **The surface directory of commands is `<plugin root>/commands`**, of hooks and modules `<plugin root>/bin/<surface>` (`lib/plugins.sh:29-35`). The registry build fails when a provided surface directory does not exist (`lib/plugins.sh:166-171`).
4. **The scan and the compile do not read the purpose.** `AOS_PURPOSE` is read only in `lib/scopes.sh`, `modules/tiers/{registration-dir,adapter-dir,hook-target}.sh` and passed through by `lib/compiler.sh:199` and `lib/capability.sh:27` (volatile list). The purpose therefore steers where authoring writes, not what compiles: a `commands/commands.yaml` in the plugin root with `commands` in `provides` should compile in a session with the purpose `project`. Not run.
5. **The namespace is a field of the registration entry.** `commands/commands.yaml` of the framework documents `namespace` as required ("e.g. aos, git"); output goes to `${PROVIDER_CONFIG_DIR}/commands/<namespace>/<id>.md` (`docs/capability-wiring.md`, Step 4). The prefix is not derived from the plugin name.

## Gap

`lib/compiler.sh:477-493` (`_assemble_command_body`) builds the body of a `type: script` command as:

```
resolved=$(capability_substitute_vars "${BU_ROOT}/commands/${script_val}")
COMMAND_EXECUTE="[[push:bash ${resolved} "$ARGUMENTS" 2>&1; echo "EXIT=$?"]]"
```

The script is always looked up under the framework's `commands/` directory (the three existing script commands point at `aos/compile.sh`, `aos/config.sh`, `aos/planning.sh`). No tier chain and no `PLUGIN_ROOT` is involved: `PLUGIN_ROOT` expands only per file of a plugin tier (`lib/capability.sh:59-81`), and this call passes no file. A plugin, and equally a project, cannot ship a script for a script command.

The other command types do not fit a wrapper of `bash app git <name>`:

- `type: tool`: `templates/commands/tool.md` is `$COMMAND_TOOL_DISPATCH`, which `grep -rn` finds nowhere in `lib`, `adapters`, `modules` or `docs`. The comment at `lib/compiler.sh:460` says the non-script types are "not yet active"; `docs/capability-surfaces.md` describes `tool` as "Tool dispatch, LLM validates output".
- `type: agent`: blueprint-assembled and spawns a registered agent; heavy for a wrapper.

## Options (not decided)

1. Framework change: resolve `script` through the tier chain or against `PLUGIN_ROOT` of the registering plugin tier. This is a change in the agentic-os project.
2. Registration workaround: `script: "../app git release"` with `forward-arguments: true`. The concatenation in `lib/compiler.sh:488` is unquoted, so the line would read `bash ${BU_ROOT}/commands/../app git release "$ARGUMENTS"`. This is a reading of the code; it was not compiled and the effect of `app lint` on it is unknown.
3. Leave the slash commands out of the plugin and use `bash app git <command>`.

## Not checked

- No compile was run (`app compile commands`), so the compiled artifact for a plugin command is unseen.
- `app lint` rules for command registrations, and `script_contract_problems` (`lib/scripts.sh`) on a script value, were not read.
- Whether a session with the purpose `deliverable` can claim a task of PLAN-plugin: `plans.json` of the session registers the plan; no command that adopts a plan into another session was found among `app plan` commands.
- How the dynamic authoring pipeline (`command-author`) places its files when the purpose is `deliverable`.

## Effect on PLAN-plugin

T4.13 describes the slash commands as script commands forwarding to `bash app git <name>`, written into the plugin root from a session with the purpose `deliverable`. Point 4 shows the purpose is not needed for the compile; the Gap shows the script form cannot work from the plugin tier without option 1 or 2. T4.13 stays as written until the developer has checked these points; the plan is changed only through `/aos:plan`.
