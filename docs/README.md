# git-workflow manuals

`edotz.git-workflow` is the plugin that gives edotz repositories one local-first git process: the daily loop (branch, commit, check, pull request), releases from conventional commits, promote, split to child repositories and branch rulesets. These manuals describe the process, everything the plugin offers and what a consuming project has to do.

## Where to start

| You are | Start with | Then |
|---|---|---|
| New to the plugin | [Overview](overview.md) | [Daily loop](daily-loop.md) |
| A developer working in a project that uses it | [Daily loop](daily-loop.md) | [Command reference](command-reference.md), [Troubleshooting](troubleshooting.md) |
| Moving a repository onto the plugin | [Adopting the plugin in a project](adopting-in-a-project.md) | [Configuration](configuration.md), [Rulesets and CI](rulesets-and-ci.md) |
| Releasing | [Release and promote](release-and-promote.md) | [Monorepo and split](monorepo-and-split.md) for components with child repositories |
| Looking after the GitHub App and token service | [GitHub App and token service](github-app-and-token-service.md) | [Rulesets and CI](rulesets-and-ci.md) |
| Maintaining or extending the plugin | [Architecture](architecture.md) | [Command reference](command-reference.md) |

## The manuals

| Manual | Answers |
|---|---|
| [Overview](overview.md) | What the plugin is, the branch model, components, stages, the actors, a glossary |
| [Daily loop](daily-loop.md) | How a change goes from a clean `master` to a merged pull request, and the clean-up afterwards |
| [Command reference](command-reference.md) | Every `app git` command and slash command: synopsis, options, environment, exit codes |
| [Release and promote](release-and-promote.md) | How a version is decided, what a release does, pre-releases, promote and its baseline mode |
| [Monorepo and split](monorepo-and-split.md) | Components of a monorepo, split to child repositories, baselines and legacy tags |
| [Configuration](configuration.md) | `components.yaml`, environment variables, stages, commitlint, cliff, token sets |
| [Rulesets and CI](rulesets-and-ci.md) | Branch rulesets, `rules-sync`, `status-checks.yml`, hooks and shims |
| [GitHub App and token service](github-app-and-token-service.md) | The App, permission sets, how tokens are issued, hosting, key custody, security |
| [Adopting the plugin in a project](adopting-in-a-project.md) | Prerequisites, the step by step adoption, three worked cases, a checklist |
| [Troubleshooting](troubleshooting.md) | Symptoms, causes and fixes, and what never to do |
| [Architecture](architecture.md) | Layout, modules and libraries, the tool image, hooks, tests, how to extend, known gaps |

## The process in five lines

1. `app git start <type> <name>` opens a branch and a worktree from `master`.
2. `app git commit` writes a conventional commit; `app git check` runs the minimum check.
3. `app git pr` pushes the branch and opens the pull request; it is squash-merged, so its title becomes the commit on `master`.
4. `app git release` counts the version from the `feat`, `fix`, `perf` and breaking commits since the last tag, then commits, tags and publishes it with a short-lived App token.
5. `app git promote <tag>` moves the release branch to the release tag; `app git split` sends components of a monorepo to their child repositories.

## Conventions of these manuals

- Commands are written as `bash app git <command>` in examples and `app git <command>` in prose; they run from the root of the consuming project.
- Docker is a prerequisite: git, `gh`, git-cliff and splitsh-lite run in the plugin's tool image.
- A rule that the plugin enforces is stated as a rule; a rule that only convention holds is marked as such.
