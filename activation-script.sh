#!/bin/sh
cd /runner
curl -o actions-runner-linux-x64-2.315.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.315.0/actions-runner-linux-x64-2.315.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.315.0.tar.gz
RUNNER_ALLOW_RUNASROOT=true ./config.sh --unattended  --acceptteeeula --url https://github.com/moosj-be --token AHCZGP5VE5BZCWZNZP2NV23GD6NZC