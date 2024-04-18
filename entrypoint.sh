#!/bin/bash

ORG=$ORG
PAT=$PAT
NAME=$NAME
ACTIONS_RUNNER_INPUT_REPLACE=true

REG_TOKEN=$(curl -X POST -H "Authorization: Bearer ${PAT}" -H "Accept: application/vnd.github+json" https://api.github.com/orgs/${ORG}/actions/runners/registration-token | jq .token --raw-output)

cd /actions-runner

echo $NAME
RUNNER_ALLOW_RUNASROOT=1 ./config.sh --unattended --url https://github.com/${ORG} --token ${REG_TOKEN} --name $NAME --replace

cleanup() {
echo "Removing runner..."
    ./config.sh remove --token ${REG_TOKEN}
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup' SIGTERM

echo "Starting runner..."
./run.sh & wait $!