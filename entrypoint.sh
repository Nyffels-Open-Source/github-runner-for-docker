#!/bin/bash
set -Eeuo pipefail

# =====================
# Environment variables (preserved)
# =====================
ORG="${ORG}"
PAT="${PAT}"
NAME="${NAME:-$(hostname)-ephemeral}"
HOSTDOCKER="${HOSTDOCKER:-0}"
export RUNNER_WORK_DIRECTORY="${RUNNER_WORK_DIRECTORY:-_work}"
export ACTIONS_RUNNER_INPUT_REPLACE=true
export RUNNER_ALLOW_RUNASROOT=1

_CLEANED_UP="false"
_runner_pid=""

# =====================
# Cleanup function
# =====================
cleanup() {
  if [[ "${_CLEANED_UP}" == "true" ]]; then
    return 0
  fi
  _CLEANED_UP="true"

  echo "🧹 Cleaning up runner registration..."

  # =======[ CHANGE START ]====================================================
  if [[ -n "${_runner_pid}" ]] && kill -0 "${_runner_pid}" 2>/dev/null; then
    echo "↪️  Stopping runner process PID=${_runner_pid}..."
    kill -TERM "${_runner_pid}" 2>/dev/null || true

    for i in {1..10}; do
      if kill -0 "${_runner_pid}" 2>/dev/null; then
        sleep 1
      else
        break
      fi
    done
    if kill -0 "${_runner_pid}" 2>/dev/null; then
      echo "⛔ Runner still alive, killing..."
      kill -KILL "${_runner_pid}" 2>/dev/null || true
    fi
  fi


  REMOVE_TOKEN="$(curl -s -X POST \
    -H "Authorization: Bearer ${PAT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/${ORG}/actions/runners/remove-token" \
    | jq -r '.token // empty')"

  if [[ -n "${REMOVE_TOKEN}" ]]; then
    echo "🔐 Remove token acquired, removing runner non-interactively..."
    ( cd /actions-runner && ./config.sh remove --token "${REMOVE_TOKEN}" --unattended ) || true
  else
    echo "⚠️  Could not obtain remove token; attempting best-effort unattended removal..."
    ( cd /actions-runner && ./config.sh remove --unattended ) || true
  fi

  echo "🧼 Cleaning workspace (${RUNNER_WORK_DIRECTORY})..."
  rm -rf "${RUNNER_WORK_DIRECTORY}"/* || true

  if [[ "$HOSTDOCKER" == "1" ]]; then
    echo "🐳 Cleaning up Docker containers and resources for this runner..."
    docker ps -aq --filter "label=runner-owner=${NAME}" | xargs -r docker rm -f || true
    docker images -q --filter "label=runner-owner=${NAME}" | xargs -r docker rmi -f || true
    echo "✅ Docker cleanup complete (filtered by label 'runner-owner=${NAME}')"
  fi
}

on_term() {
  echo "🛑 Caught TERM"
  cleanup
  exit 0
}
on_int() {
  echo "🛑 Caught INT"
  cleanup
  exit 130
}
trap on_term TERM
trap on_int INT
trap cleanup EXIT

# =====================
# Validate required variables
# =====================
if [[ -z "${PAT}" ]]; then
  echo "❌ Error: PAT environment variable is not set"
  exit 1
fi
if [[ -z "${ORG}" ]]; then
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
  "${API_URL}" | jq -r '.token // empty')

if [[ -z "${REG_TOKEN}" ]]; then
  echo "❌ Failed to retrieve registration token"
  exit 1
fi

echo "✅ Registration token received"

# =====================
# Prepare runner directory
# =====================
cd /actions-runner

if [[ ! -f ./config.sh ]]; then
  echo "❌ config.sh not found in $(pwd). Exiting."
  ls -al
  exit 1
fi

# =====================
# Preflight check: remove stale local config if GitHub doesn't know the runner
# =====================
echo "🔎 Checking for stale local configuration..."
if [[ -f ".runner" ]]; then
  echo "⚠️ Local .runner config exists. Checking if GitHub knows about this runner..."

  RUNNER_ID=$(curl -s -H "Authorization: Bearer ${PAT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/${ORG}/actions/runners" \
    | jq -r --arg NAME "$NAME" '.runners[] | select(.name==$NAME) | .id // empty')

  if [[ -z "${RUNNER_ID}" ]]; then
    echo "🧹 Stale local config detected. Removing local runner configuration..."
    rm -f .runner
  else
    echo "✅ GitHub knows this runner (ID: ${RUNNER_ID})"
  fi
fi

# =====================
# Configure ephemeral runner
# =====================
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
if [[ "${HOSTDOCKER}" == "1" ]]; then
  echo "🚀 Starting Docker service..."
  service docker start || echo "⚠️ Docker service start failed"
fi

# =====================
# Launch runner
# =====================
echo "🚀 Starting runner..."

./run.sh &
_runner_pid=$!
wait "${_runner_pid}" || true
echo "ℹ️ Runner process exited."
