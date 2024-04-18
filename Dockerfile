FROM ubuntu:22.04

# Set arguments
ARG RUNNER_VERSION="2.315.0"
ARG DEBIAN_FRONTEND=nointeractive

# Install dependencies
RUN apt-get update
RUN apt install -y curl 
RUN apt install -y jq 
RUN apt install -y build-essential 
RUN apt install -y libssl-dev 
RUN apt install -y libffi-dev 
RUN apt install -y python3 
RUN apt install -y python3-venv 
RUN apt install -y python3-dev 
RUN apt install -y python3-pip
RUN apt install apt-utils

# Install docker following the dockers documentation
RUN curl -fsSL https://get.docker.com -o get-docker.sh
RUN sh get-docker.sh

# Install github action runner
RUN mkdir actions-runner && cd actions-runner \
&& curl -O -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
&& tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
RUN /actions-runner/bin/installdependencies.sh

# Copy and set entrypoint
COPY entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]