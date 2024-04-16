#!/bin/bash
if [ -f "/runner/activation-script.sh" ]; then
  /bin/bash ./runner/activation-script.sh
  rm ./runner/activation-script.sh
else
  echo "Activation script not found."
fi

echo "completed"