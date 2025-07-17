#!/bin/bash
set -e

# =====================
# Environment variables (preserved)
# =====================
ORG="${ORG}"
PAT="${PAT}"
NAME="${NAME:-$(hostname)-ephemeral}"
HOSTDOCKER="${HOSTDOCKER:-0}"
RUNNER_WORK_DIRECTORY="${RUNNER_WORK_DIRECTORY:-_work}"
ACTIONS_RUNNER_INPUT_REPLACE=true
RUNNER_ALLOW_RUNASROOT=1

# =====================
# Cleanup function
# =====================
cleanup() {
  echo "🧹 Cleaning up runner registration..."
  ./config.sh remove --unattended --token "${REG_TOKEN}" || true

  echo "🧼 Cleaning workspace (${RUNNER_WORK_DIRECTORY})..."
  rm -rf "${RUNNER_WORK_DIRECTORY}"/* || true

  if [[ "$HOSTDOCKER" == "1" ]]; then
    echo "🐳 Cleaning up Docker containers and resources for this runner..."
    docker ps -aq --filter "label=runner-owner=${NAME}" | xargs -r docker rm -f || true
    docker images -q --filter "label=runner-owner=${NAME}" | xargs -r docker rmi -f || true
    echo "✅ Docker cleanup complete (filtered by label 'runner-owner=${NAME}')"
  fi
}

# Trap signals for cleanup
trap cleanup INT TERM EXIT

# =====================
# Validate required variables
# =====================
if [[ -z "$PAT" ]]; then
  echo "❌ Error: PAT environment variable is not set"
  exit 1
fi
if [[ -z "$ORG" ]]; then
  echo "❌ Error: ORG environment variable is not set"
  exit 1
fi

# =====================
# Fetch registration token
# =====================
echo "📡 Fetching registration token from org '${ORG}'..."
API_URL="https://api.github.com/orgs/${ORG}/actions/runners/registration-token"
echo "Api URL: ${API_URL}"
REG_TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer ${PAT}" \
  -H "Accept: application/vnd.github+json" \
  "${API_URL}" | jq -r .token)

if [[ -z "$REG_TOKEN" ]]; then
  echo "❌ Failed to retrieve registration token"
  exit 1
fi

echo "✅ Registration token received"

# =====================
# Configure ephemeral runner
# =====================
cd /actions-runner

if [ ! -f ./config.sh ]; then
  echo "❌ config.sh not found in $(pwd). Exiting."
  ls -al
  exit 1
fi

echo "⚙️ Configuring ephemeral runner..."
./config.sh \
  --url "https://github.com/${ORG}" \
  --token "${REG_TOKEN}" \
  --name "${NAME}" \
  --work "${RUNNER_WORK_DIRECTORY}" \
  --unattended \
  --replace \
  --ephemeral \
  --labels "ephemeral,docker,self-hosted"

# =====================
# Start Docker service if requested
# =====================
if [[ "$HOSTDOCKER" == "1" ]]; then
  echo "🚀 Starting Docker service..."
  service docker start || echo "⚠️ Docker service start failed"
fi

# =====================
# Launch runner
# =====================
echo "🚀 Starting runner..."
./run.sh

# =====================
# Post-run cleanup
# =====================
echo "⚙️ Runner finished, performing final cleanup..."
cleanup
