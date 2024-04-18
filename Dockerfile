FROM ubuntu:22.04
FROM docker:latest

ARG RUNNER_VERSION="2.315.0"

ARG DEBIAN_FRONTEND=nointeractive

RUN apt update -y && apt upgrade -y && useradd -m docker
RUN apt install -y --no-install-recommends curl jq build-essential libssl-dev libffi-dev python3 python3-venv python3-dev python3-pip

RUN apt install apt-transport-https ca-certificates curl software-properties-common -y
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
RUN apt update
RUN apt install docker-ce -y
RUN usermod -aG docker docker

RUN cd /home/docker && mkdir actions-runner && cd actions-runner \
&& curl -O -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
&& tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

RUN chown -R docker ~docker && /home/docker/actions-runner/bin/installdependencies.sh

COPY start.sh start.sh

RUN chmod +x start.sh

USER docker

CMD service docker start
ENTRYPOINT ["./start.sh"]