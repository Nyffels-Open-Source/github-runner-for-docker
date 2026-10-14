#!/bin/bash
set -euo pipefail
SCOUT_VERSION=1.26.0
archive="docker-scout_${SCOUT_VERSION}_linux_amd64.tar.gz"
work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT
curl -fsSL --retry 3 "https://github.com/docker/scout-cli/releases/download/v${SCOUT_VERSION}/${archive}" -o "${work_directory}/${archive}"
printf '%s  %s\n' 47daa9ac442816316c65389f516b847146bb9f45e8d6afdcbb9ce835c4e138bd "${work_directory}/${archive}" | sha256sum -c -
mkdir -p "$HOME/.docker/cli-plugins"
tar -xzf "${work_directory}/${archive}" -C "$HOME/.docker/cli-plugins" docker-scout
