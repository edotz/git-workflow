# Token service: contract, authentication, fallback, hosting (PLAN-plugin T1.3)

Settles what the concept decisions D6 (the CLI gets a short-lived installation token from a token service) and D23 and D48 (design and authentication left to the plan) leave open. It rests on the plan decisions D4, D5, D15, D16 and D17 and on the verified rows of `verify-github.md`. It holds no service code.

## Client contract

- **Request.** The CLI sends one HTTPS request per command run with three things: the developer's GitHub token (from the developer's own `gh` login) as the credential, the repository (`owner/name`), and the permission set the command needs, named by command.
- **Response.** An installation token of the App and its `expires_at`, or a refusal with a reason (see Fallback).
- **Narrowing.** The service issues the token for that one repository and only the permissions of the named set. Measured on 2026-11-03: a request for `contents: write` on the sandbox repository returned a token with `contents: write` and `metadata: read` on that repository only.
- **Lifetime.** One hour, fixed by GitHub (measured: issued 11:21:41, expires 12:21:41 UTC). The service does not extend it. The CLI asks for a new token on every command run and never reuses one.
- **Permission sets by command**, taken from the verified rows:
  - release `--apply`, promote, the push of a split component, and the creation of the GitHub Release: contents write (rows L261, L411, L441 and L654 all ran with it).
  - pull request handling: pull requests write.
  - rules-sync: administration write. Row L500: with administration read the App can read the repository rulesets but a write is refused with 403; with write it succeeded.
  - No command asks for packages: row L467, an App token with packages write is refused when it creates an organisation package, so a package publish stays a consumer workflow with the built-in token.
  - No command asks for workflows: the App has no Workflows permission, so a release commit cannot change files under `.github/workflows`.
  - No command asks for an organisation permission: row L500, `GET /orgs/{org}/rulesets` returned 403. The sync uses repository rulesets.
- **Repository.** The service refuses a repository the App is not installed on, which includes a child repository of a split component until the App is installed there.
- **Delivery to the tool call.** The CLI keeps the token in memory and hands it to the tool container as an environment variable by name, so the value is not in the command line. It is never written to a file, an image or the developer's shell, and it is dropped when the command ends. A `git` push uses it through an `http.extraheader` setting in the environment, not a URL; row L261 pushed a commit and a tag that way.
- **Logging.** Neither the service nor the CLI logs the developer's token or the installation token.
- **Order.** A command fetches its token before its first write.

## Authentication

- **Rule (D4).** The service accepts an existing `gh` login: the developer's token proves who they are, and the service checks that this login is an active member of the organisation. Only members get a token. The developer's token is used for that proof only; the service neither stores it nor acts with it. Every write is made by the App.
- **Check.** `GET /user` identifies the login and `GET /user/memberships/orgs/<org>` returns the state. Observed with the developer's login of scopes `repo` and `workflow`: both return 200, and the membership state is `active`, so no `read:org` scope is needed.
- **Authorisation.** Organisation membership is the only criterion; there are no roles per repository.
- **Removal.** A member removed from the organisation is refused at the next request. Tokens already issued run out within one hour.
- **Not run.** The check was run with one developer's login, an administrator. It was not run with a fine-grained token, with a login of another scope set, or with a login that is not a member.

## Fallback

- **Fail closed (D5).** When the service is unreachable, or refuses, the command that needs a token stops with a non-zero exit and a message that names the reason: service unreachable, login not accepted, not a member, repository not installed. There is no second path: no personal token and no token issued by hand (D4, D30).
- **What keeps working.** Everything that reads or computes locally needs no installation token: commit, commit message lint, the local checks and `release --dry-run`.
- **What stops.** `release --apply`, promote, the push of a split component, the creation of the GitHub Release and rules-sync.
- **No half-done state.** Because a command fetches its token before its first write, a refusal leaves nothing written. A command that fails after its first write is repaired by running it again, because the release is idempotent: it detects the pushed tag and creates only what is missing (white paper, section 8.1).
- **Consequence accepted.** While the service is down, nobody releases. The way out is to restore the service, not to bypass it.

## Service hosting

- **Platform (D25).** A Docker container on the developer's own machine, chosen 2026-11-03. The image holds the service code and its configuration: the organisation, the App ID and the permission set of each command. The private key is not in the image: it is a read-only file on the host, mounted into the container at run time. This machine is the one declared exception to "the key is not on a developer machine"; D16 holds otherwise.
- **Reach (D26).** The service operates on this machine only, to learn how it works and to change it. It listens locally and is not exposed to other machines; a developer on another machine gets no token (D5). A shared endpoint would be a later decision.
- **Requirements the platform has to meet:**
  - an HTTPS endpoint that developer machines can reach;
  - the App's private key only in the platform's secret store, never in a repository, an image, a log or on a developer machine (D6);
  - no logging, storing or forwarding of developer tokens or installation tokens;
  - refusal of non-members, and issue of narrowed tokens only;
  - as its own configuration: the organisation, the App ID and the permission set of each command.
- **Key custody (D16).** The key exists only in the service's secret store, with no backup. An organisation owner generates it and rotates it by generating a new key and deleting the old one. A lost key is replaced, not recovered.
- **Test key.** The key of the sandbox App lies on a developer machine for the checks of T1.1. It belongs to a test App, is no production key, and is deleted from that machine when the sandbox is retired.
