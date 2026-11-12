# Plugin files a project uses

Paths are relative to the plugin root named in the skill; `components.yaml` and `.env` are
relative to the root of the project.

| File | What it is | What a project does with it |
|---|---|---|
| `.github/workflows/status-checks.yml` | the only CI workflow: commit lint, title lint, declared checks | copy to the same path in the project |
| `commitlint.config.mjs` | the conventional commit rules, header limit 100 | copy to the project root; CI reads the project copy, the local lint reads the plugin copy, keep them equal |
| `bin/config/rulesets.yaml` | the data of the rulesets `master`, `release` and `legacy` | read only; `rules-sync` applies it |
| `bin/config/token-service.json` | the permission sets `contents`, `split` and `administration` | read only; the token service image holds a copy, rebuild it after a change |
| `bin/config/cliff.toml` | the release filter: only `feat`, `fix`, `perf` and breaking commits | read only |
| `.git-templates/hooks/commit-msg`, `pre-push` | the git hook shims | installed by `shims`, not copied by hand |
| `docker-compose.yaml`, `.docker/Dockerfile` | the token service and the tool image | start the service from the plugin root |
| `components.yaml` (project root) | the components: name, paths, checks, version files, split | write it in the project; the schema is in the configuration manual |
