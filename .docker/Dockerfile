ARG IMAGE_BASE

FROM ${IMAGE_BASE} AS fetch
ARG GIT_CLIFF_VERSION
ARG GIT_CLIFF_SHA512
ARG SPLITSH_VERSION
ARG SPLITSH_SHA256
ARG GH_VERSION
ARG GH_SHA256

RUN set -eu; \
    for v in GIT_CLIFF_VERSION GIT_CLIFF_SHA512 SPLITSH_VERSION SPLITSH_SHA256 GH_VERSION GH_SHA256; do \
        eval "test -n \"\${$v}\"" || { echo "build arg $v is empty" >&2; exit 1; }; \
    done; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    mkdir /dl /out; cd /dl; \
    curl -fsSLO "https://github.com/orhun/git-cliff/releases/download/v${GIT_CLIFF_VERSION}/git-cliff-${GIT_CLIFF_VERSION}-x86_64-unknown-linux-gnu.tar.gz"; \
    echo "${GIT_CLIFF_SHA512}  git-cliff-${GIT_CLIFF_VERSION}-x86_64-unknown-linux-gnu.tar.gz" | sha512sum -c -; \
    tar -xzf "git-cliff-${GIT_CLIFF_VERSION}-x86_64-unknown-linux-gnu.tar.gz" -C /out --strip-components=1 "git-cliff-${GIT_CLIFF_VERSION}/git-cliff"; \
    curl -fsSLO "https://github.com/splitsh/lite/releases/download/v${SPLITSH_VERSION}/lite_linux_amd64.tar.gz"; \
    echo "${SPLITSH_SHA256}  lite_linux_amd64.tar.gz" | sha256sum -c -; \
    tar -xzf lite_linux_amd64.tar.gz -C /out ./splitsh-lite; \
    curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz"; \
    echo "${GH_SHA256}  gh_${GH_VERSION}_linux_amd64.tar.gz" | sha256sum -c -; \
    tar -xzf "gh_${GH_VERSION}_linux_amd64.tar.gz" -C /out --strip-components=2 "gh_${GH_VERSION}_linux_amd64/bin/gh"

FROM ${IMAGE_BASE} AS tool
ARG GIT_APT_VERSION

RUN set -eu; \
    test -n "${GIT_APT_VERSION}" || { echo "build arg GIT_APT_VERSION is empty" >&2; exit 1; }; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates jq "git=${GIT_APT_VERSION}"; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY --from=fetch /out/git-cliff /out/splitsh-lite /out/gh /usr/local/bin/

WORKDIR /workspace

FROM node:22-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da AS token-service
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts
COPY bin/modules/git/token-service.mjs ./bin/modules/git/token-service.mjs
COPY bin/config/token-service.json ./bin/config/token-service.json
USER node
EXPOSE 8790
CMD ["node", "bin/modules/git/token-service.mjs"]
