To secure a seamless planning and implementation phase, **yes, you should close 3 to 4 critical architectural gaps now**.

While tactical details (such as whether release notes carry an LLM summary or the exact regex for version file replacement) can safely wait for the plan, leaving structural contracts open creates friction and contradictory assumptions across modules.

---

### Critical Gaps to Close Before Planning (High Impact)

#### 1. The Container Invocation Contradiction (D36 vs. D53)

* **The Gap:** D36 dictates that *"Modules run the tools with `docker exec` in a running container with identical host and container paths"*, but D53 lists *"an ephemeral container per call"* as an open candidate while stating *"D36 stands."*
* **Why it blocks planning:** `docker exec` and `docker run --rm` require completely different plugin foundations:
* If using `docker exec`: The plugin must implement a daemon lifecycle manager (checking container health, starting `docker compose up -d` on demand, handling host reboots, pruning stale containers per repo/machine, and handling multi-worktree volume mounts).
* If using `docker run --rm` (ephemeral): The runner library requires only a single stateless wrapper (`docker run --rm -v "$(pwd):$(pwd)" -w "$(pwd)" ...`) with zero background state to manage.




* **Recommendation:** Settle D53 now on **stateless, ephemeral execution (`docker run --rm`)**, and update D36 to eliminate `docker exec`. Managing background daemon containers across multiple projects and Git worktrees introduces unnecessary state drift.

#### 2. The Component Declaration Contract (D44 & D46)

* **The Gap:** D44 and D46 defer the format of the component declaration and workspace graph integration to the plan.
* **Why it blocks planning:** The core operations of `app git release`, `app git split`, and `status-checks.yml` cannot be designed without a concrete data model. The planner needs to know where component boundaries are defined.
* **Recommendation:** Settle on a single root manifest (e.g., `components.yaml` or a dedicated block in `.agentic-os/project.yaml`) with explicit fields:
```yaml
components:
  - name: web
    workspace: hh-website          # Auto-resolves paths via workspace graph (D46)
    version_files: [apps/web/package.json]
  - name: typo3
    paths: [apps/typo3-hub]
    version_files: [apps/typo3-hub/ext_emconf.php]
  - name: infra
    paths: [infra]
    version: none

```


Settling this contract immediately unlocks parallel planning for the status-check generator, the `git-cliff` path filter, and the `splitsh-lite` runner.

#### 3. Token Service Interface & Credential Injection (D6 & D48)

* **The Gap:** D48 defers developer authentication and token service design to the plan.
* **Why it blocks planning:** Every write operation to GitHub (`app git release --apply`, `app git split`, `app git rules-sync`, `app git promote`) relies on an installation token from the GitHub App. The planner needs to know:
* How does the host CLI authenticate to the token service?
* How is the short-lived token handed down to `gh` and Git inside the container?


* **Recommendation:** Settle the boundary contract:
* *Authentication:* The CLI passes the developer's local `gh auth token` to an internal HTTPS endpoint to prove GitHub organization membership.
* *Injection:* The service returns an ephemeral installation token ($\le 60\text{ min}$), which the host exports as `GH_TOKEN` / `GITHUB_TOKEN` and passes into the Docker environment (`-e GH_TOKEN`) for HTTPS Git and GitHub API calls.





#### 4. GitHub "Latest Release" Collision in Monorepos (D42)

* **The Gap:** D42 defers how GitHub's repository-wide "latest release" works across multiple independent components.
* **Why it blocks planning:** If component A (`web/v0.1.0`) and component B (`typo3/v0.1.0`) are released independently, each standard `gh release create` call overwrites the repository's single `releases/latest` pointer on GitHub.


* **Recommendation:** Settle the convention:
* All component release calls must pass `--latest=false` to `gh release create`.


* Repository documentation badges (Shields.io) and README references must explicitly link to specific component release tags (e.g., `releases/tag/web/v...`), never to generic `/releases/latest`.





---

### Gaps That Can Safely Remain Deferred ("The Plan Settles It")

The following items are low risk and belong naturally to detailed implementation:

* **D45 (Quick checks selection):** Can be configured per project in the project settings or manifest.
* **D47 (Pre-release flags):** Standard flag forwarding (`--pre=<channel>`) to `git-cliff` and semver generation.


* **D49 (LLM summary in release notes):** An optional layer that enriches the changelog header via `provider_run_prompt` without affecting the Git state.


* **D50 (Version file writers):** File-specific IO parsers (JSON, PHP regex) that can be developed modularly under `bin/lib/writers/`.


* **D43 (Child repo force-push baseline):** A procedural checklist item during initial repo migration rather than an architectural pivot.



---

### Suggested Actionable Updates

To lock the architecture and secure the plan, add the following settlements:

1. **D53 (Resolved):** Standardize on **ephemeral containers (`docker run --rm`)** per tool execution; adjust D36 accordingly to remove daemon/exec dependencies.
2. **D55 (New):** Standardize the **monorepo component manifest** at the repository root using structured YAML (mapping Turborepo workspace packages or explicit directory paths).
3. **D56 (New):** Specify the **Token Service boundary** (authenticated via developer `gh` session, returning an ephemeral token passed into Docker as `GH_TOKEN`).
4. **D57 (New):** Enforce `--latest=false` on all multi-component releases to avoid tag collisions on GitHub.