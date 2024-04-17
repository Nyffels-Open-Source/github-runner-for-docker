#!/bin/sh
cd /runner
echo 'Download file'
curl -s -o actions-runner-linux-x64-2.315.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.315.0/actions-runner-linux-x64-2.315.0.tar.gz
echo 'unpack file'
tar xzf ./actions-runner-linux-x64-2.315.0.tar.gz
echo 'Run script'
./config.sh --url https://github.com/Nyffels-IT --token AHCZGP2OV2KUFLTNYLCPW6TGD5WMC