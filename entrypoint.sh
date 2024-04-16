#!/bin/bash
if [ -f "/runner/activation-script.sh" ]; then
  echo "Activation-script found"
  /bin/bash ./runner/run.sh
  rm ./runner/run.sh
  echo "Activation-script completed"
else
  echo "Activation script not found."
fi

echo "completed"