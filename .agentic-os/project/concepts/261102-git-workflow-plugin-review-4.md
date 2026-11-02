Yes, you should close **three critical architectural gaps** and resolve **one internal contradiction** before moving to the implementation plan.

While tactical details (like regex patterns for version file writers or LLM prompt formatting) can safely wait, leaving core data schemas, execution paradigms, and authentication boundaries open will force the planning phase to design around moving targets.

---

### Gaps to Close Now

#### 1. The Component Declaration & Workspace Contract (D44 & D46)

* **The Gap:** The concept defers the declaration schema (D44) and whether JavaScript workspaces automatically infer paths via Turborepo (D46) to the plan.
* **Why it blocks planning:** The core plugin modules—`app git release`, `app git split`, `git-cliff` argument construction, and the generation of `status-checks.yml`—cannot even design their internal data interfaces without knowing how components are declared and parsed.


* **Recommended Settlement:** Define the contract now based on Appendix B of the whitepaper:


* Store declarations in a single file at the repository root (`components.yaml` or a top-level `components:` block in `.agentic-os/project.yaml`).


* Support two path-resolution modes: `workspace: <name>` (delegates path and dependency detection to `turbo --affected` / `pnpm-workspace.yaml`) and `paths: [...]` (explicit glob list for CMS, infrastructure, or standalone libraries).


* Include explicit fields: `name`, `version: yes|none`, `version_files: [...]`, and `split: yes|no`.





#### 2. Terminate the Container Daemon Debate (D55)

* **The Gap:** D55 fixes Docker as the tool provider but leaves open whether tool calls use `docker exec` against a persistent background container or ephemeral containers per call (`docker run --rm`).
* **Why it blocks planning:** These two paths require completely different software designs:
* If using `docker exec`: The plugin must build and maintain a complex daemon manager (health-checking containers, auto-starting `docker compose up -d`, handling host reboots, cleaning stale containers, and managing multi-worktree mounts).


* If using `docker run --rm`: The entire tool invocation layer collapses into a single stateless, self-cleaning bash wrapper.




* **Recommended Settlement:** Decide on **ephemeral containers (`docker run --rm`)**. A persistent container daemon introduces fragile state management across terminal sessions and repository worktrees for negligible performance gains.



#### 3. Define the Token Service Interface Boundary (D6, D23, D48)

* **The Gap:** D20 correctly places the *implementation* of the token service out of scope, but D48 defers how the CLI interacts with it to the plan.
* **Why it blocks planning:** Every remote write action (`app git release --apply`, `app git promote`, `app git split`, `app git rules-sync`) depends on this token. Without an I/O contract, the planning of `bin/lib/github.sh` is blocked.


* **Recommended Settlement:** Specify the client-side exchange contract:
* The CLI calls a lightweight fetcher helper: `token_service_get_token`.
* The helper authenticates the developer using their existing host session (e.g., passing the output of `gh auth token` as a bearer token to verify GitHub organization membership).


* The service returns a temporary GitHub App installation token ($\le 60\text{ min}$), which the host exports as `GH_TOKEN` / `GITHUB_TOKEN` and passes into the ephemeral container calls.





#### 4. Resolve the Command Surface Contradiction (D41 vs. D51)

* **The Contradiction:** D41 explicitly settles the command surface:
> *"Commands are `app git start`, `commit`, `pr`, `release`, `promote`, `split` and `rules-sync`..."*


Yet D51 is still listed in the concept's register as open:
> *"D51 [decided] Whether split and rules-sync live in the git domain or in their own domain -> The plan settles it."*


* **Recommended Settlement:** Mark D51 as superseded by D41. Keeping all operations under the unified `app git` domain aligns with Principle P4 ("One entry point") and avoids scattering commands across disjointed namespaces.



---

### Gaps That Can Safely Remain Deferred to the Plan

The remaining items in the "Still open" list are safe to leave for the detailed planning phase:

* **Child repository baseline force-push (D43):** This is a one-time migration execution step for existing split repositories, not an architectural unknown.


* **Quick checks selection (D45):** Can be declared as a simple string or command list in the project's workflow configuration.


* **Pre-release handling (D47):** A matter of mapping CLI flags (`--pre=<channel>`) down to `git-cliff` arguments.


* **LLM changelog summary (D49):** An optional, non-blocking enrichment via `provider_run_prompt`.


* **Version file writers (D50):** Modular, format-specific parser scripts (e.g., `jq` for `package.json`, regex for `ext_emconf.php`).


* **Adapting `branch-cleanup` and `workflow-status` (D25):** Low-level Git query adjustments to inspect squash commits on `master` rather than relying on `git branch --merged`.



Closing the component schema, the container execution model, and the token interface boundary will give your planning phase an unshakeable foundation.