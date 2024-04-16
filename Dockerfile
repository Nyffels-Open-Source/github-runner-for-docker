FROM ubuntu:latest
LABEL maintainer="chesney@nyffels.be"

RUN apt-get update && apt install docker.io -y
RUN usermod -aG docker root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /runner
COPY activation-script.sh /runner

RUN chmod +x /runner/activation-script.sh