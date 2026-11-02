The decided concept in `CONCEPT-git-workflow-plugin` resolves the structural flaws of the earlier draft: it formally abandons the commit-replay mechanism, places the release commit squarely on `master`, and simplifies the release branch to a pure fast-forward pointer.

However, by shifting from ephemeral execution to a daemonized container (`docker exec`) and permitting unvetted direct pushes to `master` during the development phase, the new concept introduces subtle operational risks that must be addressed before implementation.

---

### 1. Key Architectural Wins Over the Previous Draft

* **Elimination of the Replay Trap (D27, D28, D33):** Placing the atomic release commit (manifests, `CHANGELOG.md`, `README.md`) directly on `master` ensures that `master` remains the definitive single source of truth for version history. Relegating the release branch (`RELEASE_BRANCH`, e.g., `2.x`) to a pure fast-forward tracker eliminates patch-ID collisions, backport PRs, and branch divergence.


* **Resolved Actor Model (D30):** The previous contradiction where `master` had no bypass actor is resolved. The GitHub App is now the sole bypass actor on both `master` and the release branches for pushing release commits, tags, and promotions, while humans remain strictly governed by rulesets in production.


* **Release Artifact Closure (D39, D40):** Defining the plugin boundary at the release object and generating the GitHub Release via API (with `--draft` capabilities) provides a clean handoff. Downstream package publishing (npm, Packagist) and deployments can cleanly subscribe to `release: published` webhooks without polluting the Git plugin with cloud deployment logic.


* **Path-Filtered Component Versioning (D38):** Adopting `<component>/vX.Y.Z` tags driven by file paths—while allowing unversioned components (`version: none` for infrastructure/CI)—delivers a clean domain separation for multi-stack monorepos.



---

### 2. Critical Flaws and Operational Risks

### A. The Race Condition in Fast-Forward Promotion (D27, D28)

Under D28, the release commit is applied to `master`, and the release branch is updated later via `app git promote`.

* **The Vulnerability:** In an active team setting or during the development phase where direct pushes are allowed (D29), developers may push new feature commits to `master` *after* the release commit is created but *before* `app git promote` is executed. If `app git promote` simply runs `git merge --ff-only master`, it will fast-forward the release branch past the release commit and include unreleased, unverified feature commits.


* **Required Fix:** `app git promote` must never blindly target `origin/master`. It must fast-forward the release branch strictly to the **target release tag** (e.g., `git merge --ff-only <component>/vX.Y.Z` or the specific release commit SHA), ensuring that intermediate commits cannot leak onto the release branch.

### B. The Daemonized Container Trap (`docker exec` vs. Ephemeral Execution) (D35, D36, D37)

Deciding to run all CLI tool calls through `docker exec` in a persistent, background container introduces severe edge cases:

* **Lifecycle and State Drift:** If the container must already be running, every command (`app git start`, `commit`, `release`) must check container status, start it if stopped, handle host reboots, and manage orphaned containers across multiple projects.
* **Workspace & Worktree Mounting:** Because the container relies on identical host and container paths (D36), mounting arbitrary project paths, worktrees (where `.git` points outside the current directory), and host SSH/git configs into a persistent daemon requires broad host filesystem bind-mounts. On macOS (VirtioFS) or Windows (WSL2), persistent bind mounts suffer from filesystem cache invalidation and permission mismatch issues (`uid`/`gid`).


* **Recommended Adjustment:** Reconsider ephemeral tool calls (`docker run --rm -v "$(pwd):$(pwd)" -w "$(pwd)" ...`) or a host-binary fallback shim. If Docker is mandatory for byte-identical consistency, stateless single-command execution (`docker run --rm`) is far more resilient than managing a long-running daemon per repository or per machine.



### C. Direct Pushes to `master` vs. Release Verification (D29, D32)

* **The Risk:** In the development phase, developers can push directly to `master` without CI status checks (D29). To compensate, D32 shifts quality assurance to the release step via a local "minimum check" on `HEAD` during `release --dry-run` and `release --apply`.


* **The Impact:** This turns `app git release` into an ad-hoc CI runner. If a developer has pushed a syntactically invalid change or broken unit test three days prior, nobody notices until release time, halting the release train.
* **Recommended Adjustment:** If direct pushes are allowed on `master` during the development phase, a lightweight GitHub Action should still run asynchronously on push to alert the developer immediately, rather than deferring all failure discovery to the local release invocation.



---

### 3. Evaluating the Open Questions (D42–D51)

* **Monorepo "Latest Release" Ambiguity (D42):** GitHub natively tracks only one `latest` release per repository. When releasing monorepo components independently (`web/v0.1.0` then `typo3/v0.1.0`), each publication will overwrite the `latest` badge. The CLI's GitHub Release call must pass `--latest=false` for subcomponents, and documentation links must target explicit tags rather than `/releases/latest`.


* **Child Repository Baseline Force-Push (D43):** Existing child repositories created by the legacy split action carry merge commits that do not match `splitsh-lite` tree SHAs. The concept must require an explicit confirmation flag (e.g., `app git split --force-baseline <component>`) to prevent accidental destructive overwrites during initial migration.


* **Version File Writers & Verification (D50):** The requirement to read back modified version files after writing is necessary. For PHP/Composer packages, `version` fields in `composer.json` are discouraged by Packagist (which reads tags directly); the writer should be optional per component manifest rather than mandatory across all file types.



Would you like to explore refining the container execution model from a persistent `docker exec` daemon to stateless, ephemeral runs, or would you prefer to map out the exact script implementation for the fast-forward `promote` guard?