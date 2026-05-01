# syntax=docker/dockerfile:1.7

FROM ubuntu:25.10

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set arguments
ARG RUNNER_VERSION=2.334.0
ARG NODE_VERSION=24.15.0
ARG NPM_VERSION=11.13.0
ARG INSTALL_DOCKER_PLUGINS=true
ARG TARGETOS
ARG TARGETARCH
ENV RUNNER_VERSION=${RUNNER_VERSION}
ENV NODE_VERSION=${NODE_VERSION}
ENV NPM_VERSION=${NPM_VERSION}

# Install dependencies
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
# hadolint ignore=DL3008
RUN apt-get update && \
    ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime && \
    apt-get full-upgrade -y && \
    apt-get install -y --no-install-recommends ca-certificates curl jq unzip xz-utils tzdata libicu76 && \
    dpkg-reconfigure -f noninteractive tzdata && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install GitHub Actions runner (with checksum verification)
WORKDIR /actions-runner
RUN ARCH_SUFFIX="" && \
    NODE_ARCH="" && \
    if [ "${TARGETOS:-linux}" != "linux" ]; then \
      echo "Unsupported TARGETOS='${TARGETOS}'. This Docker image builds Linux runners only." ; exit 1 ; \
    fi && \
    case "${TARGETARCH:-amd64}" in \
      amd64) ARCH_SUFFIX="linux-x64"; NODE_ARCH="x64" ;; \
      arm64) ARCH_SUFFIX="linux-arm64"; NODE_ARCH="arm64" ;; \
      *) echo "Unsupported TARGETARCH='${TARGETARCH}'" ; exit 1 ;; \
    esac && \
    RUNNER_TGZ="actions-runner-${ARCH_SUFFIX}-${RUNNER_VERSION}.tar.gz" && \
    curl -fsSL -o "${RUNNER_TGZ}" "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TGZ}" && \
    CHECKSUM="$(curl -fsSL "https://api.github.com/repos/actions/runner/releases/tags/v${RUNNER_VERSION}" | \
      jq -r --arg name "${RUNNER_TGZ}" '.assets[] | select(.name==$name) | .digest // empty' | \
      sed 's/^sha256://')" && \
    if [ -z "${CHECKSUM}" ]; then echo "Failed to resolve checksum for ${RUNNER_TGZ} via GitHub API digests"; exit 1; fi && \
    echo "${CHECKSUM}  ${RUNNER_TGZ}" | sha256sum -c - && \
    tar xzf "${RUNNER_TGZ}" && \
    rm "${RUNNER_TGZ}" && \
    if [ -d "/actions-runner/externals/node24" ]; then \
      NODE_TGZ="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" && \
      curl -fsSL -o "${NODE_TGZ}" "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TGZ}" && \
      NODE_CHECKSUM="$(curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | awk "/ ${NODE_TGZ}\$/ {print \$1}")" && \
      if [ -z "${NODE_CHECKSUM}" ]; then echo "Failed to resolve checksum for ${NODE_TGZ}"; exit 1; fi && \
      echo "${NODE_CHECKSUM}  ${NODE_TGZ}" | sha256sum -c - && \
      rm -rf /actions-runner/externals/node24/* && \
      tar -xJf "${NODE_TGZ}" --strip-components=1 -C /actions-runner/externals/node24 && \
      rm "${NODE_TGZ}" && \
      rm -rf /actions-runner/externals/node24/include \
             /actions-runner/externals/node24/share \
             /actions-runner/externals/node24/lib/node_modules/corepack/shims ; \
    fi && \
    if [ -d "/actions-runner/externals/node24_alpine" ] && [ -d "/actions-runner/externals/node24" ]; then \
      rm -rf /actions-runner/externals/node24_alpine/* && \
      cp -a /actions-runner/externals/node24/. /actions-runner/externals/node24_alpine/ ; \
    fi && \
    for NODE_DIR in /actions-runner/externals/node*; do \
      [ -d "${NODE_DIR}" ] || continue ; \
      if [ -x "${NODE_DIR}/bin/node" ] && [ -f "${NODE_DIR}/lib/node_modules/npm/bin/npm-cli.js" ]; then \
        "${NODE_DIR}/bin/node" "${NODE_DIR}/lib/node_modules/npm/bin/npm-cli.js" --prefix "${NODE_DIR}" install -g "npm@${NPM_VERSION}" --no-audit --no-fund && \
        "${NODE_DIR}/bin/node" "${NODE_DIR}/lib/node_modules/npm/bin/npm-cli.js" cache clean --force || true ; \
      fi ; \
    done

# Prevent mount errors by preparing dummy repo path
RUN mkdir -p /actions-runner/_work/_dummy/_dummy

# Install Docker (DinD) from official apt repository
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    printf '%s\n' \
      "Types: deb" \
      "URIs: https://download.docker.com/linux/ubuntu" \
      "Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")" \
      "Components: stable" \
      "Architectures: $(dpkg --print-architecture)" \
      "Signed-By: /etc/apt/keyrings/docker.asc" \
      > /etc/apt/sources.list.d/docker.sources
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get full-upgrade -y && \
    apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io && \
    if [ "${INSTALL_DOCKER_PLUGINS}" = "true" ]; then \
      apt-get install -y --no-install-recommends docker-buildx-plugin docker-compose-plugin ; \
    fi && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    (sed -i -e 's/ulimit -Hn/ulimit -n/g' /etc/init.d/docker || true) && \
    if [ "${INSTALL_DOCKER_PLUGINS}" = "true" ]; then \
      docker buildx version && docker compose version ; \
    fi

# Label image for traceability
LABEL runner-owner="ephemeral-runner"

STOPSIGNAL SIGTERM

# Healthcheck to ensure runner container is alive
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD pgrep -f Runner.Listener || exit 1

# Copy entrypoint
COPY --chmod=0755 entrypoint.sh /entrypoint.sh
RUN useradd --create-home --shell /bin/bash --uid 1001 --no-log-init runner && \
    chown -R runner:runner /actions-runner

# Default to root so DinD works out-of-the-box.
# For least privilege in host-socket mode, users can still override with `--user 1001:1001`.
# hadolint ignore=DL3002
USER 0

# Set default entrypoint
ENTRYPOINT ["/entrypoint.sh"]
