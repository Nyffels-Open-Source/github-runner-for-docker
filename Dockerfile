FROM ubuntu:latest
LABEL maintainer="chesney@nyffels.be"

RUN apt-get update && apt install docker.io -y
RUN usermod -aG docker root

WORKDIR /runner
COPY activation-script.sh /runner
COPY entrypoint.sh /

# ENTRYPOINT [ "/entrypoint.sh" ]