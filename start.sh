#!/bin/bash

ORG=$ORG
PAT=$PAT

REG_TOKEN=$(curl -X POST -H "Authorization: Bearer ${PAT}" -H "Accept: application/vnd.github+json" https://api.github.com/orgs/${ORG}/actions/runners/registration-token | jq .token --raw-output)

echo "${REG_TOKEN}"

cd /home/docker/actions-runner

./config.sh --unattended --url https://github.com/${ORG} --token ${REG_TOKEN}

cleanup() {
echo "Removing runner..."
    ./config.sh remove --unattended --token ${REG_TOKEN}
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup' SIGTERM

echo "Starting runner..."
./run.sh & wait $!