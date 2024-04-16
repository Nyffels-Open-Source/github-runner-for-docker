#!/bin/bash
if test -f "./runner/run.sh"; then
  echo "Activation-script found"
  /bin/bash ./runner/run.sh
  rm ./runner/run.sh
  echo "Activation-script completed"
fi