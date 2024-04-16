#!/bin/bash
if test -f "./runner/activation-script.sh"; then
  echo "Activation-script found"
  /bin/bash ./runner/run.sh
  rm ./runner/run.sh
  echo "Activation-script completed"
fi

echo "completed"