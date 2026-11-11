# Tool image check of PLAN-plugin T2.4

Run 2026-11-03 by the agent at the developer's request, on the development machine. It holds no secret.

## Machine

- Operating system: Debian GNU/Linux 12 (bookworm) on WSL2, kernel 6.18.54.1-microsoft-standard-WSL2.
- Docker: server 24.0.7.
- Not a second machine: the development machine, where `git-cliff` and `splitsh-lite` are not installed (`command -v` finds neither).
- Both tags of the image (`edotz-git-workflow-tools:2.8.0-2.103.3` and the hash tag) were removed with `docker rmi` before each run.
- The Docker layer cache was warm: the apt layer and the download layer were reused, so the first call below did not download the tools. The base image was present locally. A cold build was timed separately.

## Result

- `tool_run git-cliff --version` printed `git-cliff 2.8.0`.
- `tool_run gh --version` printed `gh version 2.103.3 (2026-10-26)`.
- `tool_run splitsh-lite --prefix=p` on a one-commit test repository printed the commit `a1f46ee2b9330cd8ae59bd36aef368fc3e12dc9d` and `1 commits created, 1 commits traversed, in 5ms`.
- First call, with the image removed and the layer cache warm: 0.99 s, which includes the compose build, the tagging and the container run. The next call: 0.49 s.
- Cold build, `docker compose build --no-cache tools` after removing the image: 13 s on this machine, with every download checked against its checksum.
- Not covered: a machine with no Docker layers and no local base image, a machine without network access to GitHub releases, and an arm64 host (the image is linux/amd64 only, D21). A second machine has not run this check.
