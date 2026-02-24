FROM ubuntu:24.04

# Set arguments
ARG RUNNER_VERSION=2.331.0
ARG NODE_VERSION=24.13.0
ARG NPM_VERSION=11.6.2
ARG TARGETARCH
ENV RUNNER_VERSION=${RUNNER_VERSION}
ENV NODE_VERSION=${NODE_VERSION}
ENV NPM_VERSION=${NPM_VERSION}

# Install dependencies
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
RUN apt-get update && \
    ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime && \
    apt-get install -y --no-install-recommends ca-certificates curl jq apt-utils unzip xz-utils tzdata && \
    apt-get upgrade -y && \
    dpkg-reconfigure -f noninteractive tzdata && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install GitHub Actions runner (with checksum verification)
RUN mkdir -p /actions-runner && cd /actions-runner && \
    ARCH_SUFFIX="" && \
    NODE_ARCH="" && \
    case "${TARGETARCH:-amd64}" in \
      amd64) ARCH_SUFFIX="linux-x64"; NODE_ARCH="x64" ;; \
      arm64) ARCH_SUFFIX="linux-arm64"; NODE_ARCH="arm64" ;; \
      *) echo "❌ Unsupported TARGETARCH='${TARGETARCH}'" ; exit 1 ;; \
    esac && \
    RUNNER_TGZ="actions-runner-${ARCH_SUFFIX}-${RUNNER_VERSION}.tar.gz" && \
    curl -fsSL -o "${RUNNER_TGZ}" "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TGZ}" && \
    CHECKSUM="$(curl -fsSL "https://api.github.com/repos/actions/runner/releases/tags/v${RUNNER_VERSION}" | \
      jq -r --arg name "${RUNNER_TGZ}" '.assets[] | select(.name==$name) | .digest // empty' | \
      sed 's/^sha256://')" && \
    if [ -z "${CHECKSUM}" ]; then echo "❌ Failed to resolve checksum for ${RUNNER_TGZ} via GitHub API digests"; exit 1; fi && \
    echo "${CHECKSUM}  ${RUNNER_TGZ}" | sha256sum -c - && \
    tar xzf "${RUNNER_TGZ}" && \
    rm "${RUNNER_TGZ}" && \
    if [ -d "/actions-runner/externals/node24" ]; then \
      NODE_TGZ="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" && \
      curl -fsSL -o "${NODE_TGZ}" "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TGZ}" && \
      NODE_CHECKSUM="$(curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | awk "/ ${NODE_TGZ}\$/ {print \$1}")" && \
      if [ -z "${NODE_CHECKSUM}" ]; then echo "❌ Failed to resolve checksum for ${NODE_TGZ}"; exit 1; fi && \
      echo "${NODE_CHECKSUM}  ${NODE_TGZ}" | sha256sum -c - && \
      rm -rf /actions-runner/externals/node24/* && \
      tar -xJf "${NODE_TGZ}" --strip-components=1 -C /actions-runner/externals/node24 && \
      rm "${NODE_TGZ}" && \
      rm -rf /actions-runner/externals/node24/include \
             /actions-runner/externals/node24/share \
             /actions-runner/externals/node24/lib/node_modules/corepack/shims ; \
    fi && \
    for NODE_DIR in /actions-runner/externals/node*; do \
      [ -d "${NODE_DIR}" ] || continue ; \
      if [ -x "${NODE_DIR}/bin/npm" ]; then \
        "${NODE_DIR}/bin/npm" --prefix "${NODE_DIR}" install -g "npm@${NPM_VERSION}" --no-audit --no-fund && \
        "${NODE_DIR}/bin/npm" cache clean --force || true ; \
      fi ; \
    done

# Prevent mount errors by preparing dummy repo path
RUN mkdir -p /actions-runner/_work/_dummy/_dummy    

# Install Docker (DinD) from official apt repository
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
RUN apt-get update && \
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i -e 's/ulimit -Hn/ulimit -n/g' /etc/init.d/docker || true

# Label image for traceability
LABEL runner-owner="ephemeral-runner"

# Healthcheck to ensure runner container is alive
HEALTHCHECK CMD pgrep -f Runner.Listener || exit 1

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && \
    useradd --create-home --shell /bin/bash --uid 1001 runner && \
    chown -R runner:runner /actions-runner

# Default to non-root user for least privilege
USER 1001

# Set default entrypoint
ENTRYPOINT ["/entrypoint.sh"]
