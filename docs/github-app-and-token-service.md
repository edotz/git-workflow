# GitHub App and token service

The plugin does its privileged writes (release, promote, split, rulesets) as a GitHub App, `git-workflow-app`, and not with a personal token. A token service on the developer's machine issues the App's short-lived installation tokens, narrowed to one repository and one permission set, to members of the organisation who prove their login. This manual explains the design, the permissions, how a token is issued, how the service is hosted and how its key is kept, what happens when it is down, how to add a repository, and what an attacker could do with a token.

The commands are in [Command reference](command-reference.md). The config that the service reads is in [Configuration](configuration.md#token-servicejson).

## Why an App and not personal tokens

| Concern | Answer |
|---|---|
| Who is the actor of a release or a ruleset change | The App. Every write is made by the App, so the history shows the App and not one developer's account. |
| How much a token can do | An installation token covers one repository and only the permissions of one set. A personal token carries every right of its owner in every repository. |
| How long a token lives | One hour, fixed by GitHub. The service does not extend it; the CLI asks for a new one on every run. |
| Who can get one | Active members of the organisation. Removing a member stops new tokens at the next request. |
| What a developer must hold | Nothing beyond the normal `gh` login. The plugin's commands never use the developer's login for rulesets, releases or splits. |
| When the service is down | The privileged commands stop. There is no fallback to a personal token; see [Fallback](#fallback). |

The service is the one place that holds the App's private key. Developers do not hold it.

## The App

| Property | Value |
|---|---|
| Name | `git-workflow-app` |
| Owner | the organisation `edotz` |
| Installable on | that account only |
| Installation | on selected repositories, not all of them |
| Events and webhooks | none |
| App ID | the numeric ID; set as `GIT_WORKFLOW_APP_ID` for `rules-sync --apply` and as `TOKEN_SERVICE_APP_ID` for the service |

A sandbox App on a test repository was used before the production App to check the permission model. Consuming projects do not use it, and no command of the plugin refers to it.

### Permission sets

The service asks GitHub for a token with exactly the permissions of one set in `bin/config/token-service.json`. A request for a set the file does not list is refused.

| Set | Permission granted | Used by | Why this level |
|---|---|---|---|
| `contents` | `contents: write` | `release --apply` (release commit, tag, GitHub Release); `promote --apply` (moves the release branch) | a push of a commit and a tag needs write |
| `split` | `contents: write`, `workflows: write` | `split --apply` (pushes to a child repository) | the child receives the component's history, which may hold changes to `.github/workflows` |
| `administration` | `administration: write` | `rules-sync --apply` | creating and updating rulesets needs administration write; read only is refused with 403 |

The App also holds `metadata: read`, which GitHub gives every App.

The App does not hold packages write or any organisation permission. Its repository permissions are administration write, contents write, pull requests write, workflows write and metadata read.

### What the App cannot do

| Action | Why it is refused |
|---|---|
| Publish an npm or any other package to the organisation | The App has no packages permission. A token with packages write was refused when it created an organisation package. No command asks for it. Package publishing stays a job of the consuming project, with the built-in token of its own workflow. |
| Change a file under `.github/workflows` with a release or promote token | The `contents` set carries no workflows permission, and the service narrows the token to it, so GitHub refuses the write even though the App holds the permission. Only a `split` token can write workflow files. |
| Read or change organisation-level rulesets | The App has no organisation permission; `GET /orgs/{org}/rulesets` answered 403. `rules-sync` uses repository rulesets. |
| Act on a repository outside the installation | The service refuses a repository the App is not installed on (`repository not installed`). |
| Use a token on another repository | Each token is narrowed to the one repository of its request. |
| Push or open a pull request as the developer | Not needed; `pr` uses the developer's own login, and the App is not involved. |

The `split` set exists because the permission of the App alone is not enough: the service narrows every token to the set of the command, so without a set that names `workflows: write` a push of workflow files to a child is refused. The service image holds `token-service.json`, so after a change of the file the image has to be rebuilt (`docker compose --env-file .env.defaults build token-service`) and the service restarted. See [Monorepo and split](monorepo-and-split.md) for when a child needs its first push.

## How an installation token is issued

The CLI does the request in `bin/lib/token.sh` (`token_fetch`). The service does the rest in `bin/modules/git/token-service.mjs`.

### The request

The CLI sends one `POST /token` to `TOKEN_SERVICE_URL` (default `http://127.0.0.1:8790`):

```text
POST /token
Authorization: Bearer <developer login token from gh auth token>
Content-Type: application/json

{"repo": "owner/name", "set": "contents"}
```

The CLI sends the request without a proxy. The header and the body are read by curl from a pipe, so neither is on a command line or in a file. The request times out after 20 seconds.

### The checks of the service

The service runs these steps in order. The first failure stops the request.

| # | Check | Refusal (HTTP status and message) |
|---|---|---|
| 1 | the request is `POST /token` | 404 `no such endpoint` |
| 2 | the `Authorization` header is a bearer token | 401 `login not accepted` |
| 3 | the body is at most 4096 bytes | 413 `request too large` |
| 4 | the body is JSON | 400 `request is not JSON` |
| 5 | `set` is listed in `token-service.json` | 400 `permission set unknown` |
| 6 | `repo` is `owner/name` with the usual name characters | 400 `repository must be owner/name` |
| 7 | the owner of `repo` is the organisation (case insensitive) | 403 `repository not in the organisation` |
| 8 | `GET /user` with the developer's token returns a login | 401 `login not accepted` |
| 9 | `GET /user/memberships/orgs/<org>` returns state `active` | 403 `not a member` |
| 10 | the App is installed on the repository (`GET /repos/<owner>/<name>/installation`) | 404 `repository not installed` |
| 11 | GitHub issues an installation token for that repository and the permissions of the set | 502 `token service failed` |

On success the service answers with the token, its `expires_at`, the permissions and the repository. It logs one line with the login, the repository and the set. It never logs a token.

The service keeps no token and no developer token. It uses the developer's token for steps 8 and 9 only.

### Authentication of developers

- A developer is authenticated by the `gh` login they already use. The CLI reads the token with `gh auth token`. There is no separate login for the plugin.
- A login is accepted when it is an active member of the organisation. No repository role is checked: membership is the only criterion.
- A removed member is refused at the next request. A token issued before the removal runs out within the hour.
- The check of the membership was verified with an administrator's login with the scopes `repo` and `workflow`. The membership endpoint answered with no `read:org` scope needed. Logins with other scope sets and fine-grained tokens are not verified.

### Lifetime and handling in the CLI

- A token lives one hour, as GitHub sets it. The service does not change that.
- The CLI asks for a token once per command run, before the first write of that run, and never reuses one.
- The token is held in the shell variable `GH_TOKEN`, not exported. It is passed to the tool container by variable name, not on a command line, and the variable is dropped when the command ends (`token_drop`).
- A command that refuses at this step writes nothing. The release command can be run again after a failure: it detects a pushed tag and creates only what is missing.

### Which command asks for which set

| Command | Set | Stops when the service refuses |
|---|---|---|
| `release --apply` | `contents` | yes, before the release commit |
| `promote --apply` | `contents` | yes, before the release branch moves |
| `split --apply` | `split` | yes, before the child is pushed |
| `rules-sync --apply` | `administration` | yes, before any ruleset is written |

The dry runs of these commands do not call the service.

## Hosting

The service runs as the container `token-service` of `docker-compose.yaml` in the plugin root, on the machine that holds the key.

| Property | Value |
|---|---|
| Image | built from the `token-service` stage of `.docker/Dockerfile`; Node 22 base image pinned by digest; `npm ci --omit=dev --ignore-scripts` |
| Image content | the service code and `bin/config/token-service.json`; no key |
| User | `TOKEN_SERVICE_UID`:`TOKEN_SERVICE_GID`, default `1000:1000` |
| Root filesystem | read only |
| Privileges | `no-new-privileges` |
| Key | a host file mounted read only at `/run/secrets/app-key.pem`; the host path is set by `TOKEN_SERVICE_KEY_FILE` |
| Port | container port 8790, published on `127.0.0.1` only, as `TOKEN_SERVICE_PORT` (default 8790) |
| Restart policy | `no`: the container does not start again after a reboot of the machine or a Docker restart |
| Logs | JSON file driver, five files of 5 MB each |

The service listens on all addresses inside the container (`TOKEN_SERVICE_HOST=0.0.0.0`). Only the loopback publish makes it reachable from the machine, so no other machine on the network can reach it. Started on the host with `app git token-service`, it listens on `127.0.0.1` unless `TOKEN_SERVICE_HOST` says otherwise.

### Start and stop

Run these from the plugin root. The `.env.defaults` file carries the image pins, and the `.env` file of the plugin root carries the App ID and the key file path. Compose needs both files, as the header of `.env.defaults` says.

```bash
docker compose --env-file .env.defaults --env-file .env up -d --build token-service
```

Check that the service answers. A request without a token gets 401, which shows the service is up and refuses an anonymous call:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8790/token
```

The expected output is `401`.

Stop it at the end of the work session:

```bash
docker compose --env-file .env.defaults --env-file .env stop token-service
```

Read the log without printing a token; the log holds login names and repository names only:

```bash
docker compose --env-file .env.defaults --env-file .env logs --tail 50 token-service
```

A line `token service listening on 8790 for org edotz` shows a start. A line `refused status=<code> reason=<reason>` shows a refusal with its reason. A line `failed unexpected error` shows a failure of the service itself; the response is 502.

### Without Docker

`bash app git token-service` runs the same code on the host. It needs Node, the dependencies installed with `npm ci` in the plugin root, and the two variables `TOKEN_SERVICE_APP_ID` and `TOKEN_SERVICE_KEY_PATH` set in the environment. It refuses to start when either is missing, and when the file at the key path has no private key in it.

## Key custody

The private key of the App is the most sensitive secret of the plugin. The rule:

1. An owner of the organisation generates the key in the App's settings on GitHub.
2. The key is stored once, as a file that only the operating system user of the service can read, outside every repository.
3. The key is mounted read only into the container. It is never copied into an image, a repository, a log, a shell history or a developer's environment.
4. No backup of the key is kept. A lost key is replaced: generate a new key, put it in place of the old file, restart the service, then delete the old key in the App's settings.
5. A suspected leak is answered the same way as a loss: generate a new key, switch, delete the old one.

The service reads the key once, when it starts. After a rotation, restart the service.

Never write the key's path or its content into a repository, a ticket, a log or a document. The variable `TOKEN_SERVICE_KEY_FILE` holds the path in the `.env` of the plugin root; that file is ignored by git.

## Fallback

The service is the only source of installation tokens. When it is unreachable or refuses, the command that needs a token stops with a message that names the reason; a refusal is followed by the HTTP status, the repository and the set:

| Message | Meaning |
|---|---|
| `token: service unreachable: <url>` | nothing listens at the address, or the request timed out |
| `token: login not accepted` | `gh` has no login, or GitHub did not accept the login |
| `token: not a member` | the login is not an active member of the organisation |
| `token: repository not installed` | the App is not installed on the repository |
| `token: refused by the service: <reason>` | any other refusal |

What keeps working without a token:

- `commit`, the commit message lint, `check`, `pr` (with the developer's login), `start`, `shims`, the dry runs of `release`, `promote`, `split` and `rules-sync`.

What stops:

- `release --apply`, `promote --apply`, `split --apply` and `rules-sync --apply`.

There is no second path. The plugin does not fall back to a personal token, and nobody issues a token by hand. Restore the service and run the command again. Because the token is fetched before the first write, the refusal leaves nothing half done.

## Adding a repository to the App

The App is installed on selected repositories. A repository the App is not installed on is refused by the service, so the step is needed for each new repository and for each child repository of a split.

1. An owner of the organisation opens the App's installation settings on GitHub and adds the repository to the selection.
2. Check the answer of the service for the new repository with a token that is discarded at once. The status code is printed, the body is not:

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8790/token \
     -H @<(printf 'Authorization: Bearer %s\n' "$(gh auth token)") \
     -H 'Content-Type: application/json' \
     -d '{"repo":"owner/name","set":"contents"}'
   ```

   The developer's token is read from a pipe and does not appear on the command line.

   The expected output is `200`. `404` means the repository is not installed yet; `403` with `not a member` means the login is not an active member.

3. The repository is now ready for `release`, `promote` and `split`. For `rules-sync --apply` the repository also needs `GIT_WORKFLOW_APP_ID` in its `.env`, so that the App is the bypass actor of its rulesets.

The App's permissions are set once for the App, not per repository. Adding a repository does not change them.

## Security

### What an attacker with a token can do

| Token | Scope | Lifetime | What it allows in the repository |
|---|---|---|---|
| installation token, `contents` | one repository | one hour | push branches and tags, create releases, move the release branch. The App is a bypass actor of the rulesets, so the pushes pass `master` and `release`. |
| installation token, `administration` | one repository | one hour | create, change or delete rulesets and branch protection of that repository, including the bypass actor list. |
| installation token, `split` | one repository | one hour | the same as `contents`, and also change files under `.github/workflows` of that repository, which runs code in its CI. |

An installation token cannot reach another repository, cannot publish a package, and cannot read organisation settings.

### What an attacker with a developer's login can do

The service issues a token for any repository of the organisation where the App is installed, for any set in the file, to any active member. A stolen developer login is therefore enough to get any of these tokens for one hour per request. This is the most important weakness of the design: the service checks membership, not roles per repository or per set. Mitigations:

- Keep the set of members small and remove a leaving member from the organisation at once.
- Keep the permission sets narrow in `token-service.json`; the `administration` set is the one to guard.
- Watch the service log for `issued` lines of an unexpected login, repository or set.

### What an attacker on the machine can do

The service listens on the loopback address of the machine. Any process of the machine that can read the developer's `gh` credential can call it. Keep the machine to the people who hold the key and the logins, and do not expose the port.

### What limits the damage

- A token covers one repository and one set, and expires within the hour.
- The service keeps no token and writes no token to a log, a file or an image; the tests check that the container log holds no token.
- The CLI holds the token in a non-exported variable and drops it at the end of the command.
- The App cannot publish packages and cannot read organisation rulesets, and only a `split` token can change workflow files.

### Responses

| Event | Response |
|---|---|
| a developer's login is lost or leaves | remove the member from the organisation; the next request is refused |
| a suspected leak of the key | generate a new key, switch the service to it, restart, delete the old key |
| an unexpected `issued` line | remove the login from the organisation, review the rulesets and the releases of the repository |
| a set that is wider than needed | narrow it in `token-service.json`, rebuild the image, restart |

## Related

- [Configuration](configuration.md): the settings of the token service and `token-service.json`.
- [Rulesets and CI](rulesets-and-ci.md): what `rules-sync --apply` writes with the `administration` token.
- [Release and promote](release-and-promote.md): the commands that use the `contents` token.
- [Monorepo and split](monorepo-and-split.md): the `split` set and the child repositories.
- [Adopting in a project](adopting-in-a-project.md): adding the repositories of a project to the App.
- [Troubleshooting](troubleshooting.md): the refusal messages and what to do with each.
