FROM ubuntu:24.04

# Set arguments
ARG RUNNER_VERSION=2.326.0
ENV RUNNER_VERSION=${RUNNER_VERSION}

# Install dependencies
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
RUN apt-get update && \
    ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime && \
    apt install -y ca-certificates curl jq build-essential libssl-dev libffi-dev \
    python3 python3-venv python3-dev python3-pip apt-utils unzip && \
    dpkg-reconfigure -f noninteractive tzdata && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install GitHub Actions runner (with checksum verification)
RUN mkdir -p /actions-runner && cd /actions-runner && \
    RUNNER_TGZ="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" && \
    curl -fsSL -o "${RUNNER_TGZ}" "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TGZ}" && \
    CHECKSUM="$(curl -fsSL "https://api.github.com/repos/actions/runner/releases/tags/v${RUNNER_VERSION}" | \
      jq -r --arg name "${RUNNER_TGZ}" '.assets[] | select(.name==$name) | .digest // empty' | \
      sed 's/^sha256://')" && \
    if [ -z "${CHECKSUM}" ]; then echo "❌ Failed to resolve checksum for ${RUNNER_TGZ} via GitHub API digests"; exit 1; fi && \
    echo "${CHECKSUM}  ${RUNNER_TGZ}" | sha256sum -c - && \
    tar xzf "${RUNNER_TGZ}" && \
    rm "${RUNNER_TGZ}"

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
HEALTHCHECK CMD pgrep -f config.sh || exit 1

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set default entrypoint
ENTRYPOINT ["/entrypoint.sh"]
