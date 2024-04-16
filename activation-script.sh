#!/bin/sh
curl -L https://github.com/actions/runner/releases/download/v2.315.0/actions-runner-linux-x64-2.315.0.tar.gz > runner.tar.gz
tar -xzf ./runner.tar.gz
rm -f ./runner.tar.gz
./config.sh --url https://github.com/moosj-be --token AHCZGP4GRM4MYPAOFVOYHMTGD3SYA