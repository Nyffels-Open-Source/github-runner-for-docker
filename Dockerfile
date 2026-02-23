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

# Label image for traceability
LABEL runner-owner="ephemeral-runner"

# Healthcheck to ensure runner container is alive
HEALTHCHECK CMD pgrep -f config.sh || exit 1

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set default entrypoint
ENTRYPOINT ["/entrypoint.sh"]
