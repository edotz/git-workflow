`CONCEPT-git-workflow-plugin` establishes a solid foundation by targeting local-first determinism, replacing personal tokens with a GitHub App, and removing the legacy multi-PR release cascades. However, this draft reflects an intermediate state (circa October 2026) that still contains critical friction points, architectural contradictions, and deferred decisions that have since been superseded or solved in the November 2026 whitepaper (`261102-git-workflow-whitepaper.md`) and process specifications (`261102-git-workflow-process.md`).

The following review details the conceptual blockers in the current draft and provides the required alignment steps.

---

### 1. Architectural Blockers and Internal Inconsistencies

#### The "Promotion and Replay" Trap (D9, D12, Q12)

* **The Flaw:** The draft retains a standing release branch (`RELEASE_BRANCH` / `2.x`) and attempts to solve code promotion by "replaying" squashed commits from `master` onto `2.x`. As noted in the draft's own risk register, replaying squashed commits against previous release commits inevitably causes patch-ID and merge conflicts whenever commits touch version manifests or documentation.


* **The Alignment:** Dissolve Q12 and replace D12 entirely. Adopt the whitepaper’s core decision: **release directly on the development branch (`master`)**. Master becomes the canonical source of truth for versions, manifests, and tags. Standing release branches and promotion workflows are eliminated; `RELEASE_BRANCH` is reserved strictly for optional, long-lived maintenance/backport lines (e.g., `1.x`).



#### Master Bypass Contradiction (D5 vs. Release Push)

* **The Flaw:** D5 states: *"master has no bypass for anyone."* However, if releases happen on `master` without a PR, an automated actor must push the release commit and tag directly to the protected branch.


* **The Alignment:** Revise D5. The GitHub App must be configured as the **sole bypass actor** (`bypass_mode: always`) on every released branch, including `master`. Regular developers remain strictly barred from direct pushes and must go through PR gates.



#### Container Model Contradiction (D3 vs. D18)

* **The Flaw:** D3 dictates that *"the container entrypoint is `app`"*, while D18 states that LLM calls run on the host via `provider_run_prompt` and the container only holds deterministic tools (`git-cliff`, `splitsh-lite`, `gh`). If `app` runs inside the container, it cannot access the host session's provider adapters or workspace tier-chain without substantial path and socket leakage.


* **The Alignment:** Adopt **Model M2 (Toolbox Shim)**. `app` executes natively on the host workstation. The plugin provides a transparent shell shim: if the host has the exact pinned versions of `git-cliff` and `splitsh-lite`, it runs them natively; otherwise, it delegates execution to the lightweight container image via `docker run`. The container entrypoint is removed.



---

### 2. Monorepo Architecture & Dependency Modeling

The draft treats monorepos almost as an afterthought, relying on legacy concepts of independent packages and vague `splitsh-lite` invocations.

* **Adopt the Integrated Product Model:** A modern monorepo is not simply a bundle of split packages; it is an integrated product combining heterogeneous components (e.g., frontend, headless CMS, and infrastructure).


* **Component Declarations at the Root:** Replace the legacy `PACKAGES_DIR` and per-folder `workflow.env` files with a unified root declaration (e.g., in a structured `components` block):


* `name`: Component identifier (and commit scope).


* `paths` / `workspace`: Directory paths or Turborepo workspace packages (`turbo --affected`).


* `version`: `yes` (default) or `none` (for unversioned components like `infra` or `ci`).


* `version_files`: Target files to align during a release (`package.json`, `composer.json`, `ext_emconf.php`).


* `split`: `yes` only if downstream distribution requires an isolated repository (e.g., Packagist PHP libraries).




* **Component-Scoped Tagging:** Formalize the tag format to `<component>/vX.Y.Z` for monorepo components (reserving `vX.Y.Z` for repositories with a single root component).



---

### 3. Lifecycle Scope and Boundary Definition

* **The Missing GitHub Release Object (Q-L):** The draft specifies creating an atomic Git commit and a Git tag, but omits the creation of the GitHub Release object itself. Downstream tooling, badges (Shields.io), and consumers depend on GitHub Releases. The CLI (`app git release --apply`) must create the GitHub Release via API using the GitHub App token, including an optional `--draft` flag for manual verification.


* **Separate Git Release from Package Release (D19, P8):** The draft blurs artifact publication with Git operations. The plugin's boundary must strictly terminate at the release artifacts: the release commit, the tag, and the GitHub Release object. Downstream tasks—such as publishing to npm, updating Packagist, deploying Next.js frontends, or running `terraform apply`—belong to consuming projects and should be triggered externally by the GitHub `release: published` webhook event.



---

### 4. Resolving the "Plan Settles It" Debt

Decisions D20 through D26 defer fundamental mechanics to "the plan." Several of these must be resolved within the concept itself to prevent downstream architectural rework:

| Deferred Decision | Evaluation & Recommended Conceptual Settlement |
| --- | --- |
| **D21 (STAGE switch)** | Simplify drastically. STAGE should solely govern whether PR branch protection rules enforce rigid review thresholds or relaxed sandbox status checks during active prototyping. Eliminate the legacy "Stage Guard" PR checks.

 |
| **D22 (Local README)** | The release commit must deterministically update `README.md` versions and badges prior to committing. Avoid dynamic post-release workflows. If static versions in the README create friction, use dynamic badges reading `/releases/latest` or tag links.

 |
| **D24 (Tag format & Pre-releases)** | Settle explicitly: `<component>/vX.Y.Z` for monorepos, `vX.Y.Z` for single repos. Pre-releases append semver identifiers (e.g., `v1.2.0-beta.1`) flag-driven via `git-cliff` (`--pre <channel>`).

 |
| **D25 (Status & Branch Cleanup)** | With squash merges, `git branch --merged` will fail to recognize merged branches. The concept must state that `branch-cleanup` and `workflow-status` will check commit subjects/PR metadata against the linear log of `master` rather than relying on direct Git ancestors.

 |
| **D26 (Ruleset Migration)** | Formulate `app git rules-sync` as an idempotent REST sync against `/repos/{owner}/{repo}/rulesets`, deploying two rulesets: `ruleset-trunk` (all developers gated) and `ruleset-release` (App as bypass actor).

 |

---

### Actionable Updates for `CONCEPT-git-workflow-plugin`

1. **Update Abstract & Approach:** State clearly that releases happen directly on the active development branch (`master`), deprecating release-promotion cascades entirely.


2. **Revise D3 & D18:** Redefine the container setup as **Model M2**: `app` runs locally on the host; containerized binaries (`git-cliff`, `splitsh-lite`, `gh`) are called strictly through host-side execution shims.


3. **Revise D5 & Dissolve D12/Q12:** Establish the GitHub App as the bypass actor on `master` for atomic release pushes, and remove the commit replay mechanism.


4. **Formalize the Monorepo Product Model:** Replace unstructured package directories with declarative root component manifests that support Turborepo dependency detection and independent `<component>/vX.Y.Z` versioning.


5. **Establish the Clean Release Boundary:** Limit plugin scope to commit, tag, and GitHub Release creation, delegating package publication and deployment to the consumer repository via `release: published` triggers.