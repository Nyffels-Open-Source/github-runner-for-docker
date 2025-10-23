#!/bin/bash
set -Eeuo pipefail

ORG="${ORG}"
PAT="${PAT}"
NAME="${NAME:-$(hostname)-ephemeral}"
HOSTDOCKER="${HOSTDOCKER:-0}"
export RUNNER_WORK_DIRECTORY="${RUNNER_WORK_DIRECTORY:-_work}"
export ACTIONS_RUNNER_INPUT_REPLACE=true
export RUNNER_ALLOW_RUNASROOT=1

_CLEANED_UP="false"
_runner_pid=""
AUTH_HEADER="Authorization: token ${PAT}"

cleanup() {
  if [[ "${_CLEANED_UP}" == "true" ]]; then
    return 0
  fi
  _CLEANED_UP="true"

  echo "🧹 Cleaning up runner registration..."

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

  if [[ -f /actions-runner/config.sh && -x /actions-runner/bin/Runner.Listener ]]; then
    REMOVE_TOKEN="$(curl -s -X POST -H "${AUTH_HEADER}" -H "Accept: application/vnd.github+json" \
      "https://api.github.com/orgs/${ORG}/actions/runners/remove-token" \
      | jq -r '.token // empty')"

    if [[ -n "${REMOVE_TOKEN}" ]]; then
      echo "🔐 Remove token acquired, removing runner non-interactively..."
      ( cd /actions-runner && ./config.sh remove --token "${REMOVE_TOKEN}" --unattended ) || true
    else
      echo "⚠️  Could not obtain remove token; attempting best-effort unattended removal..."
      ( cd /actions-runner && ./config.sh remove --unattended ) || true
    fi
  else
    echo "ℹ️ Skip runner removal: /actions-runner/bin/Runner.Listener not present."
  fi

  echo "🧼 Cleaning workspace (${RUNNER_WORK_DIRECTORY})..."
  rm -rf "${RUNNER_WORK_DIRECTORY:?}/"* || true

  if [[ "$HOSTDOCKER" == "1" ]]; then
    echo "🐳 Cleaning up Docker containers and resources for this runner..."
    docker ps -aq --filter "label=runner-owner=${NAME}" | xargs -r docker rm -f || true
    docker images -q --filter "label=runner-owner=${NAME}" | xargs -r docker rmi -f || true
    echo "✅ Docker cleanup complete (filtered by label 'runner-owner=${NAME}')"
  fi
}

on_term() { echo "🛑 Caught TERM"; cleanup; exit 0; }
on_int()  { echo "🛑 Caught INT";  cleanup; exit 130; }
trap on_term TERM
trap on_int INT
trap cleanup EXIT

if [[ -z "${PAT}" ]]; then
  echo "❌ Error: PAT environment variable is not set"
  exit 1
fi
if [[ -z "${ORG}" ]]; then
  echo "❌ Error: ORG environment variable is not set"
  exit 1
fi

echo "📡 Fetching registration token from org '${ORG}'..."
API_URL="https://api.github.com/orgs/${ORG}/actions/runners/registration-token"
echo "Api URL: ${API_URL}"
REG_TOKEN=$(curl -s -X POST -H "${AUTH_HEADER}" -H "Accept: application/vnd.github+json" "${API_URL}" | jq -r '.token // empty')
if [[ -z "${REG_TOKEN}" ]]; then
  echo "❌ Failed to retrieve registration token"
  exit 1
fi
echo "✅ Registration token received"

cd /actions-runner
if [[ ! -f ./config.sh ]]; then
  echo "❌ config.sh not found in $(pwd). Exiting."
  ls -al || true
  exit 1
fi

RUNNER_VERSION="${RUNNER_VERSION:-2.321.0}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) RUNNER_ARCH="linux-x64" ;;
  aarch64) RUNNER_ARCH="linux-arm64" ;;
  *) echo "❌ Unsupported arch: $ARCH"; exit 1 ;;
esac

if [[ ! -x ./bin/Runner.Listener ]]; then
  echo "⬇️  Downloading GitHub Actions runner ${RUNNER_VERSION} for ${RUNNER_ARCH}..."
  curl -L -o runner.tgz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
  tar xzf runner.tgz && rm runner.tgz
  if [[ -x ./bin/installdependencies.sh ]]; then
    ./bin/installdependencies.sh || true
  fi
fi

mkdir -p "/actions-runner/${RUNNER_WORK_DIRECTORY}"
export RUNNER_WORK_DIRECTORY="/actions-runner/${RUNNER_WORK_DIRECTORY}"

echo "🔎 Checking for stale local configuration..."
if [[ -f ".runner" ]]; then
  echo "⚠️ Local .runner config exists. Checking if GitHub knows about this runner..."
  RUNNER_ID=$(curl -s -H "${AUTH_HEADER}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/${ORG}/actions/runners" \
    | jq -r --arg NAME "$NAME" '.runners[] | select(.name==$NAME) | .id // empty')
  if [[ -z "${RUNNER_ID}" ]]; then
    echo "🧹 Stale local config detected. Removing local runner configuration..."
    rm -f .runner
  else
    echo "✅ GitHub knows this runner (ID: ${RUNNER_ID})"
  fi
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

if [[ "${HOSTDOCKER}" == "1" ]]; then
  echo "🚀 Starting Docker service..."
  service docker start || echo "⚠️ Docker service start failed"
fi

echo "🚀 Starting runner..."
./run.sh &
_runner_pid=$!
wait "${_runner_pid}" || true
echo "ℹ️ Runner process exited."
