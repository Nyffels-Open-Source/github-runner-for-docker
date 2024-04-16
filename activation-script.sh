#!/bin/sh
curl -o actions-runner-linux-x64-2.315.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.315.0/actions-runner-linux-x64-2.315.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.315.0.tar.gz
./config.sh --url https://github.com/moosj-be --token AHCZGP4GRM4MYPAOFVOYHMTGD3SYA