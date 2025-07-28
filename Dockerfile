FROM ubuntu:22.04

# Set arguments
ARG RUNNER_VERSION=2.326.0
ENV RUNNER_VERSION=${RUNNER_VERSION}

# Install dependencies
RUN apt-get update && \
    apt install -y curl jq build-essential libssl-dev libffi-dev \
    python3 python3-venv python3-dev python3-pip apt-utils unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install GitHub Actions runner
RUN mkdir -p /actions-runner && cd /actions-runner && \
    curl -O -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Prevent mount errors by preparing dummy repo path
RUN mkdir -p /actions-runner/_work/_dummy/_dummy    

# Install Docker (DinD)
RUN curl -sSL https://get.docker.com/ | sh && \
    sed -i -e 's/ulimit -Hn/ulimit -n/g' /etc/init.d/docker || true

# Docker-in-Docker volume
VOLUME /var/lib/docker

# Add docker CLI wrapper for automatic label injection
COPY wrapdocker /opt/runner/bin/docker
RUN chmod +x /opt/runner/bin/docker

# Add docker label wrapper path to PATH
ENV PATH="/opt/runner/bin:$PATH"

# Label image for traceability
LABEL runner-owner="ephemeral-runner"

# Healthcheck to ensure runner container is alive
HEALTHCHECK CMD pgrep -f config.sh || exit 1

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set default entrypoint
ENTRYPOINT ["/entrypoint.sh"]
