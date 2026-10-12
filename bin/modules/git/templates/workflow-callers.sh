#!/bin/bash
# Workflow Caller Templates
# Heredoc templates for GitHub Actions workflow file generation.
# Source this file before calling generate_workflow_callers().
#
# Variables used (set by generator before env_substitute_vars calls):
#   WF_REPO_OWNER          — GitHub org/owner (e.g. edotz)
#   WF_RELEASE_BRANCH      — release branch name (e.g. 0.x)
#   WF_MAIN_BRANCH         — main branch name (e.g. master)
#   WF_RELEASE_TYPE        — node | php | simple
#   WF_PROJECT_TYPE        — passed to generate-readme-action
#   WF_BACKPORT_FILES      — space-separated list of files to backport
#   WF_PACKAGE_MATRIX_JSON — JSON array of {local_path, split_repository}
#   WF_PACKAGES_DIR        — packages directory (monorepo only)
#   WF_MONOREPO_REPO       — owner/repo of monorepo (package only)
#   WF_MONOREPO_PACKAGE    — package name within monorepo packages dir (package only)
#   WF_STAGE               — production | development

# ============================================================================
# STATUS-CHECKS — inline jobs (shared by single + monorepo)
# ============================================================================

# File header — static trigger block
WF_TMPL_STATUS_CHECKS_HEADER=$(cat <<'EOF'
# GENERATED — do not edit manually. Source: bin/modules/git/templates/workflow-callers.sh via workflow-setup
name: Status Checks

on:
  pull_request:
    branches:
      - '**'

jobs:
EOF
)
export WF_TMPL_STATUS_CHECKS_HEADER

# commit-lint job block
WF_TMPL_JOB_COMMIT_LINT=$(cat <<'EOF'
  commit-lint:
    name: Validate Conventional Commits
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: wagoid/commitlint-github-action@v6
        with:
          configFile: commitlint.config.mjs
          commitDepth: 1
EOF
)
export WF_TMPL_JOB_COMMIT_LINT

# biome job block
WF_TMPL_JOB_BIOME=$(cat <<'EOF'
  biome:
    name: Biome Code Quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: biomejs/setup-biome@v2
      - name: Run Biome
        run: biome ci .
EOF
)
export WF_TMPL_JOB_BIOME

# php-cs-fixer job block
WF_TMPL_JOB_PHP_CS_FIXER=$(cat <<'EOF'
  php-cs-fixer:
    name: PHP-CS-Fixer
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: shivammathur/setup-php@v2
        with:
          php-version: '8.2'
          tools: cs2pr
      - name: Install PHP-CS-Fixer
        run: composer global require friendsofphp/php-cs-fixer --no-progress --no-interaction
      - name: Run PHP-CS-Fixer
        run: php-cs-fixer fix --dry-run --diff --format=checkstyle | cs2pr
EOF
)
export WF_TMPL_JOB_PHP_CS_FIXER

# --- job block: shellcheck ---
WF_TMPL_JOB_SHELLCHECK=$(cat <<'EOF'
  shellcheck:
    name: ShellCheck
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: ludeeus/action-shellcheck@2.0.0
        with:
          severity: warning
EOF
)
export WF_TMPL_JOB_SHELLCHECK

# eslint job block
WF_TMPL_JOB_ESLINT=$(cat <<'EOF'
  eslint:
    name: ESLint Code Quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm ci
      - run: npm run lint
EOF
)
export WF_TMPL_JOB_ESLINT

# stage-guard job — blocks direct PRs to RELEASE_BRANCH (both stages)
WF_TMPL_JOB_STAGE_GUARD=$(cat <<'EOF'
  stage-guard:
    name: Stage Guard
    runs-on: ubuntu-latest
    steps:
      - name: Block direct PRs targeting release branch
        if: github.base_ref == '$WF_RELEASE_BRANCH' && github.head_ref != '$WF_MAIN_BRANCH' && !startsWith(github.head_ref, 'release-please--')
        run: |
          echo "::error::Direct PRs to $WF_RELEASE_BRANCH are blocked. Use /git:release."
          exit 1
EOF
)
export WF_TMPL_JOB_STAGE_GUARD

# ============================================================================
# RELEASE-PIPELINE — single + package (inline release-please call)
# ============================================================================

# release-pipeline-<branch>.yml — uses release-please-action directly
WF_TMPL_RELEASE_PIPELINE=$(cat <<'EOF'
# GENERATED — do not edit manually. Source: bin/modules/git/templates/workflow-callers.sh via workflow-setup
name: Release Pipeline ($WF_RELEASE_BRANCH)

on:
  pull_request:
    branches:
      - '$WF_RELEASE_BRANCH'
    types:
      - closed
  workflow_dispatch:
    inputs:
      skip_release_please:
        description: 'Skip release-please and only run post-release steps'
        type: boolean
        default: false

jobs:
  release-please:
    if: >
      (github.event_name == 'pull_request' &&
       github.event.pull_request.merged == true) ||
      github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    env:
      FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: googleapis/release-please-action@v4
        if: ${{ github.event_name != 'workflow_dispatch' || !inputs.skip_release_please }}
        with:
          token: ${{ secrets.NPM_AUTH_TOKEN }}
          target-branch: $WF_RELEASE_BRANCH
EOF
)
export WF_TMPL_RELEASE_PIPELINE

# ============================================================================
# POST-RELEASE — single (calls _callable-post-release.yml)
# ============================================================================

WF_TMPL_POST_RELEASE=$(cat <<'EOF'
# GENERATED — do not edit manually. Source: bin/modules/git/templates/workflow-callers.sh via workflow-setup
name: Post Release ($WF_RELEASE_BRANCH)

on:
  pull_request:
    branches:
      - '$WF_RELEASE_BRANCH'
    types:
      - closed
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version to backport (e.g. 1.0.0)'
        required: true
      force_readme:
        description: 'Force README regeneration regardless of CHANGELOG diff'
        type: boolean
        default: false

jobs:
  post-release:
    if: >
      (github.event_name == 'pull_request' &&
       github.event.pull_request.merged == true &&
       startsWith(github.event.pull_request.head.ref, 'release-please--')) ||
      github.event_name == 'workflow_dispatch'
    uses: $WF_REPO_OWNER/git-workflow/.github/workflows/_callable-post-release.yml@1.x
    with:
      release_branch: '$WF_RELEASE_BRANCH'
      backport_to: '$WF_MAIN_BRANCH'
      backport_files: '$WF_BACKPORT_FILES'
      release_type: '$WF_RELEASE_TYPE'
      project_type: '$WF_PROJECT_TYPE'
      version: ${{ inputs.version || '' }}
      force_readme: ${{ inputs.force_readme || false }}
    secrets: inherit
EOF
)
export WF_TMPL_POST_RELEASE

# ============================================================================
# MERGE-SPLIT-REPO — monorepo (calls _callable-merge-split-repo.yml)
# ============================================================================

WF_TMPL_MERGE_SPLIT_REPO=$(cat <<'EOF'
# GENERATED — do not edit manually. Source: bin/modules/git/templates/workflow-callers.sh via workflow-setup
name: Merge Split Repo ($WF_RELEASE_BRANCH)

on:
  pull_request:
    branches:
      - '$WF_RELEASE_BRANCH'
    types:
      - closed

jobs:
  merge-split-repo:
    if: >
      github.event_name == 'pull_request' &&
      github.event.pull_request.merged == true
    uses: $WF_REPO_OWNER/git-workflow/.github/workflows/_callable-merge-split-repo.yml@1.x
    with:
      packages: '$WF_PACKAGE_MATRIX_JSON'
      branch: '$WF_RELEASE_BRANCH'
      organization: '$WF_REPO_OWNER'
    secrets: inherit
EOF
)
export WF_TMPL_MERGE_SPLIT_REPO

# ============================================================================
# PACKAGE: RELEASE-PIPELINE (fixed filename, no branch suffix)
# ============================================================================

WF_TMPL_PKG_RELEASE_PIPELINE=$(cat <<'EOF'
# GENERATED — do not edit manually. Source: bin/modules/git/templates/workflow-callers.sh via workflow-setup
name: Release Pipeline ($WF_RELEASE_BRANCH)

on:
  push:
    branches:
      - '$WF_RELEASE_BRANCH'
  workflow_dispatch:
    inputs:
      skip_release_please:
        description: 'Skip release-please and only run post-release steps'
        type: boolean
        default: false

jobs:
  release-please:
    uses: $WF_REPO_OWNER/git-workflow/.github/workflows/_callable-release-please.yml@1.x
    with:
      release_branch: '$WF_RELEASE_BRANCH'
      release_type: '$WF_RELEASE_TYPE'
      package_name: '$WF_PACKAGE_NAME'
    secrets: inherit
EOF
)
export WF_TMPL_PKG_RELEASE_PIPELINE

# ============================================================================
# PACKAGE: SYNC-TO-MONOREPO
# ============================================================================

WF_TMPL_PKG_SYNC_TO_MONOREPO=$(cat <<'EOF'
# GENERATED — do not edit manually. Source: bin/modules/git/templates/workflow-callers.sh via workflow-setup
name: Sync to Monorepo

on:
  pull_request:
    branches:
      - '$WF_RELEASE_BRANCH'
    types:
      - closed
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version to sync (e.g. 1.0.0)'
        required: true

jobs:
  sync-to-monorepo:
    if: >
      (github.event_name == 'pull_request' &&
       github.event.pull_request.merged == true &&
       startsWith(github.event.pull_request.head.ref, 'release-please--')) ||
      github.event_name == 'workflow_dispatch'
    uses: $WF_REPO_OWNER/git-workflow/.github/workflows/_callable-sync-to-monorepo.yml@1.x
    with:
      monorepo_repo: '$WF_MONOREPO_REPO'
      monorepo_package: '$WF_MONOREPO_PACKAGE'
      release_branch: '$WF_RELEASE_BRANCH'
      backport_files: '$WF_BACKPORT_FILES'
      release_type: '$WF_RELEASE_TYPE'
      project_type: '$WF_PROJECT_TYPE'
    secrets: inherit
EOF
)
export WF_TMPL_PKG_SYNC_TO_MONOREPO

# ============================================================================
# PACKAGE: RELEASE-PUBLISH (node only)
# ============================================================================

WF_TMPL_PKG_RELEASE_PUBLISH=$(cat <<'EOF'
# GENERATED — do not edit manually. Source: bin/modules/git/templates/workflow-callers.sh via workflow-setup
name: Release Publish

on:
  release:
    types:
      - published

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          registry-url: 'https://npm.pkg.github.com'
          scope: '@$WF_REPO_OWNER'
      - run: npm ci
      - run: npm publish
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_AUTH_TOKEN }}
EOF
)
export WF_TMPL_PKG_RELEASE_PUBLISH
