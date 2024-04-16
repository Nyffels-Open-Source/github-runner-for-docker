FROM ubuntu:latest
LABEL maintainer="chesney@nyffels.be"

RUN apt-get update && apt install docker.io -y
RUN usermod -aG docker root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN mkdir /runner
WORKDIR /runner
COPY ./activation-script.sh /runner/activation-script.sh
COPY ./entrypoint.sh /entrypoint.sh

RUN chmod +x /runner/activation-script.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]