#!/bin/bash
set -Eeuo pipefail

# -- Required/optional env ------------------------------------------------
ORG="${ORG:-}"
PAT="${PAT:-}"
NAME="${NAME:-$(hostname)-ephemeral}"
HOSTDOCKER="${HOSTDOCKER:-0}"
GITHUB_API_VERSION="${GITHUB_API_VERSION:-2022-11-28}"
RUNNER_SESSION_RETRIES="${RUNNER_SESSION_RETRIES:-3}"
RUNNER_CLEANUP_DOCKER="${RUNNER_CLEANUP_DOCKER:-1}"

export RUNNER_WORK_DIRECTORY="${RUNNER_WORK_DIRECTORY:-_work}"
export ACTIONS_RUNNER_INPUT_REPLACE=true
export RUNNER_ALLOW_RUNASROOT=1

is_truthy() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# -- Labels config --------------------------------------------------------
DEFAULT_LABELS="ephemeral,docker,self-hosted"
LABEL_MODE="${LABEL_MODE:-append}"   # append | replace
CUSTOM_LABELS="${LABELS:-}"
HOSTDOCKER_ENABLED=0
if is_truthy "$HOSTDOCKER"; then
  HOSTDOCKER_ENABLED=1
fi

normalize_labels() {
  local raw="$1"
  raw="$(printf '%s' "$raw" | tr ';' ',' | tr -d '[:space:]' | tr -s ',')"
  local IFS=','; read -ra parts <<< "$raw"
  declare -A seen; local out=()
  for p in "${parts[@]}"; do
    [[ -z "$p" ]] && continue
    if [[ -z "${seen[$p]+x}" ]]; then
      seen["$p"]=1
      out+=("$p")
    fi
  done
  (IFS=','; echo "${out[*]}")
}

case "$LABEL_MODE" in
  append|replace) ;;
  *) echo "ERROR: Invalid LABEL_MODE='$LABEL_MODE' (use 'append' or 'replace')"; exit 1 ;;
esac

if [[ -n "$CUSTOM_LABELS" ]]; then
  if [[ "$LABEL_MODE" == "replace" ]]; then
    EFFECTIVE_LABELS="$(normalize_labels "$CUSTOM_LABELS")"
  else
    EFFECTIVE_LABELS="$(normalize_labels "$DEFAULT_LABELS,$CUSTOM_LABELS")"
  fi
else
  EFFECTIVE_LABELS="$DEFAULT_LABELS"
fi

echo "Using runner labels: ${EFFECTIVE_LABELS}"

# -- Internals ------------------------------------------------------------
_CLEANED_UP="false"
_runner_pid=""
_dockerd_pid=""
_runner_configured="false"
AUTH_HEADER="Authorization: Bearer ${PAT}"
CURL_COMMON_OPTS=(--retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 10 --max-time 30 -fsSL)

api_post() {
  local url="$1"
  curl "${CURL_COMMON_OPTS[@]}" -X POST -H "${AUTH_HEADER}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION}" "${url}"
}

api_get() {
  local url="$1"
  curl "${CURL_COMMON_OPTS[@]}" -H "${AUTH_HEADER}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION}" "${url}"
}

api_delete() {
  local url="$1"
  curl "${CURL_COMMON_OPTS[@]}" -X DELETE -H "${AUTH_HEADER}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: ${GITHUB_API_VERSION}" "${url}"
}

fetch_registration_token() {
  local api_url="https://api.github.com/orgs/${ORG}/actions/runners/registration-token"
  local token

  echo "Fetching registration token from org '${ORG}'..." >&2
  echo "Api URL: ${api_url}" >&2
  token="$(api_post "${api_url}" | jq -r '.token // empty' 2>/dev/null || true)"
  if [[ -z "${token}" ]]; then
    echo "ERROR: Failed to retrieve registration token" >&2
    return 1
  fi
  echo "Registration token received" >&2
  printf '%s' "${token}"
}

clear_local_runner_config() {
  rm -f /actions-runner/.runner \
    /actions-runner/.credentials \
    /actions-runner/.credentials_rsaparams
}

clean_workspace() {
  echo "Cleaning workspace (${RUNNER_WORK_DIRECTORY})..."
  if [[ -d "${RUNNER_WORK_DIRECTORY}" ]]; then
    find "${RUNNER_WORK_DIRECTORY:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  else
    echo "INFO: Skip workspace cleanup: ${RUNNER_WORK_DIRECTORY} does not exist."
  fi
}

cleanup_docker_resources() {
  if [[ "${HOSTDOCKER_ENABLED}" == "1" ]]; then
    echo "Cleaning host Docker resources labeled runner-owner=${NAME}..."
    docker ps -aq --filter "label=runner-owner=${NAME}" | xargs -r docker rm -f || true
    docker images -q --filter "label=runner-owner=${NAME}" | xargs -r docker rmi -f || true
    echo "Host Docker cleanup complete (filtered by label 'runner-owner=${NAME}')."
    return 0
  fi

  if ! is_truthy "${RUNNER_CLEANUP_DOCKER}"; then
    echo "INFO: Docker-in-Docker cleanup disabled by RUNNER_CLEANUP_DOCKER."
    return 0
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "INFO: Skip Docker-in-Docker cleanup: Docker daemon is not reachable."
    return 0
  fi

  echo "Cleaning all Docker-in-Docker resources created by this runner..."
  docker ps -aq | xargs -r docker rm -f || true
  docker system prune --all --force --volumes || true
  docker builder prune --all --force || true
  docker volume prune --all --force || true
  echo "Docker-in-Docker cleanup complete."
}

configure_runner() {
  local registration_token="$1"

  echo "Configuring ephemeral runner..."
  ./config.sh \
    --url "https://github.com/${ORG}" \
    --token "${registration_token}" \
    --name "${NAME}" \
    --work "${RUNNER_WORK_DIRECTORY}" \
    --unattended \
    --replace \
    --ephemeral \
    --disableupdate \
    --labels "${EFFECTIVE_LABELS}"
  _runner_configured="true"
}

wait_for_docker() {
  local timeout_seconds="${1:-30}"
  local waited=0
  while (( waited < timeout_seconds )); do
    if docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

start_dind() {
  local driver="${DOCKER_DRIVER:-overlay2}"
  local data_root="${DOCKER_DATA_ROOT:-/var/lib/docker}"
  local -a extra_args=()
  if [[ -n "${DOCKERD_ARGS:-}" ]]; then
    # Intentionally split DOCKERD_ARGS on shell word boundaries for CLI-style flags.
    # shellcheck disable=SC2206
    extra_args=( ${DOCKERD_ARGS} )
  fi

  mkdir -p /var/run /var/log "${data_root}"
  rm -f /var/run/docker.pid

  echo "Starting dockerd (driver=${driver}, data-root=${data_root})..."
  dockerd \
    --host=unix:///var/run/docker.sock \
    --data-root="${data_root}" \
    --storage-driver="${driver}" \
    "${extra_args[@]}" >/var/log/dockerd.log 2>&1 &
  _dockerd_pid=$!

  if wait_for_docker 45; then
    echo "Docker daemon is ready."
    return 0
  fi

  if [[ "${driver}" != "vfs" ]]; then
    echo "WARN: dockerd did not become ready with driver '${driver}'. Retrying with 'vfs'..."
    if [[ -n "${_dockerd_pid}" ]] && kill -0 "${_dockerd_pid}" 2>/dev/null; then
      kill -TERM "${_dockerd_pid}" 2>/dev/null || true
      wait "${_dockerd_pid}" 2>/dev/null || true
    fi
    rm -f /var/run/docker.pid
    dockerd \
      --host=unix:///var/run/docker.sock \
      --data-root="${data_root}" \
      --storage-driver=vfs \
      "${extra_args[@]}" >/var/log/dockerd.log 2>&1 &
    _dockerd_pid=$!
    if wait_for_docker 45; then
      echo "Docker daemon is ready (fallback storage driver: vfs)."
      return 0
    fi
  fi

  echo "ERROR: Docker daemon did not become ready."
  echo "Last dockerd logs:"
  tail -n 200 /var/log/dockerd.log || true
  return 1
}

cleanup() {
  if [[ "${_CLEANED_UP}" == "true" ]]; then
    return 0
  fi
  _CLEANED_UP="true"

  echo "Cleaning up runner registration..."

  if [[ -n "${_runner_pid}" ]] && kill -0 "${_runner_pid}" 2>/dev/null; then
    echo "Stopping runner process PID=${_runner_pid}..."
    kill -TERM "${_runner_pid}" 2>/dev/null || true
    for _ in {1..10}; do
      if kill -0 "${_runner_pid}" 2>/dev/null; then
        sleep 1
      else
        break
      fi
    done
    if kill -0 "${_runner_pid}" 2>/dev/null; then
      echo "Runner still alive, killing..."
      kill -KILL "${_runner_pid}" 2>/dev/null || true
    fi
  fi

  cleanup_docker_resources

  if [[ -n "${_dockerd_pid}" ]] && kill -0 "${_dockerd_pid}" 2>/dev/null; then
    echo "Stopping Docker daemon PID=${_dockerd_pid}..."
    kill -TERM "${_dockerd_pid}" 2>/dev/null || true
    wait "${_dockerd_pid}" 2>/dev/null || true
  fi

  if [[ -f /actions-runner/config.sh && -x /actions-runner/bin/Runner.Listener ]] && \
     [[ "${_runner_configured}" == "true" || -f /actions-runner/.runner ]]; then
    REMOVE_TOKEN="$(api_post "https://api.github.com/orgs/${ORG}/actions/runners/remove-token" \
      | jq -r '.token // empty' 2>/dev/null || true)"

    if [[ -n "${REMOVE_TOKEN}" ]]; then
      echo "Remove token acquired, removing runner non-interactively..."
      ( cd /actions-runner && ./config.sh remove --token "${REMOVE_TOKEN}" ) || true
    else
      echo "WARN: Could not obtain remove token; local runner files will be removed."
      clear_local_runner_config
    fi
  else
    echo "INFO: Skip runner removal: runner binary not present or runner was never configured."
  fi

  clean_workspace || true
}

# -- Guards ---------------------------------------------------------------
if [[ -z "${PAT}" ]]; then
  echo "ERROR: PAT environment variable is not set"
  exit 1
fi
if [[ -z "${ORG}" ]]; then
  echo "ERROR: ORG environment variable is not set"
  exit 1
fi
if [[ ! "${RUNNER_SESSION_RETRIES}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: RUNNER_SESSION_RETRIES must be a non-negative integer"
  exit 1
fi
if [[ "${RUNNER_WORK_DIRECTORY}" = /* || "/${RUNNER_WORK_DIRECTORY}/" == *"/../"* ]]; then
  echo "ERROR: RUNNER_WORK_DIRECTORY must be a relative path within /actions-runner"
  exit 1
fi

on_term() { echo "Caught TERM"; cleanup; exit 0; }
on_int()  { echo "Caught INT";  cleanup; exit 130; }
trap on_term TERM
trap on_int INT
trap cleanup EXIT

# -- Runner install -------------------------------------------------------
cd /actions-runner
if [[ ! -f ./config.sh ]]; then
  echo "ERROR: config.sh not found in $(pwd). Exiting."
  ls -al || true
  exit 1
fi

RUNNER_VERSION="${RUNNER_VERSION:-2.334.0}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) RUNNER_ARCH="linux-x64" ;;
  aarch64|arm64) RUNNER_ARCH="linux-arm64" ;;
  *) echo "ERROR: Unsupported arch: $ARCH"; exit 1 ;;
esac

if [[ ! -x ./bin/Runner.Listener ]]; then
  echo "Downloading GitHub Actions runner ${RUNNER_VERSION} for ${RUNNER_ARCH}..."
  RUNNER_TGZ="actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
  curl -fsSL -o "${RUNNER_TGZ}" "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TGZ}"
  CHECKSUM="$(curl -fsSL "https://api.github.com/repos/actions/runner/releases/tags/v${RUNNER_VERSION}" | \
    jq -r --arg name "${RUNNER_TGZ}" '.assets[] | select(.name==$name) | .digest // empty' | \
    sed 's/^sha256://')"
  if [[ -z "${CHECKSUM}" ]]; then
    echo "ERROR: Failed to resolve checksum for ${RUNNER_TGZ} via GitHub API digests"
    exit 1
  fi
  echo "${CHECKSUM}  ${RUNNER_TGZ}" | sha256sum -c -
  tar xzf "${RUNNER_TGZ}" && rm "${RUNNER_TGZ}"
  if [[ -x ./bin/installdependencies.sh ]]; then
    ./bin/installdependencies.sh || true
  fi
fi

mkdir -p "/actions-runner/${RUNNER_WORK_DIRECTORY}"
export RUNNER_WORK_DIRECTORY="/actions-runner/${RUNNER_WORK_DIRECTORY}"
clean_workspace

# -- Stale runner deregistration ------------------------------------------
echo "Checking GitHub for existing runner named '${NAME}'..."
ENCODED_RUNNER_NAME="$(jq -rn --arg value "${NAME}" '$value | @uri')"
if ! RUNNERS_JSON="$(api_get "https://api.github.com/orgs/${ORG}/actions/runners?name=${ENCODED_RUNNER_NAME}&per_page=100")"; then
  echo "ERROR: Could not query existing GitHub runners; refusing to modify local registration state."
  exit 1
fi
if ! jq -e '.runners | type == "array"' >/dev/null 2>&1 <<< "${RUNNERS_JSON}"; then
  echo "ERROR: GitHub returned an invalid runner-list response; refusing to modify local registration state."
  exit 1
fi
RUNNER_ID="$(jq -r --arg NAME "$NAME" \
  '[.runners[] | select(.name==$NAME) | .id][0] // empty' <<< "${RUNNERS_JSON}")"
LOCAL_RUNNER_ID=""
if [[ -f ".runner" ]]; then
  LOCAL_RUNNER_ID="$(jq -r '.agentId // empty' .runner 2>/dev/null || true)"
fi

if [[ -n "${RUNNER_ID}" && "${LOCAL_RUNNER_ID}" == "${RUNNER_ID}" ]]; then
  echo "Recovering existing runner '${NAME}' (ID: ${RUNNER_ID}) from local configuration."
  _runner_configured="true"
elif [[ -n "${RUNNER_ID}" ]]; then
  echo "Found existing runner '${NAME}' (ID: ${RUNNER_ID}) on GitHub. Deregistering..."
  if ! api_delete "https://api.github.com/orgs/${ORG}/actions/runners/${RUNNER_ID}"; then
    echo "ERROR: Could not deregister stale runner '${NAME}'; refusing to replace it."
    exit 1
  fi
  clear_local_runner_config
  echo "Existing runner '${NAME}' deregistered."
elif [[ -f ".runner" ]]; then
  echo "Local .runner config found but no matching runner on GitHub. Cleaning local files..."
  clear_local_runner_config
else
  echo "No existing runner found. Proceeding with fresh registration."
fi

# -- Docker setup ---------------------------------------------------------
if [[ "${HOSTDOCKER_ENABLED}" == "1" ]]; then
  if [[ ! -S /var/run/docker.sock ]]; then
    echo "ERROR: HOSTDOCKER=1 but /var/run/docker.sock is not mounted."
    exit 1
  fi
  if ! wait_for_docker 10; then
    echo "ERROR: HOSTDOCKER=1 but Docker daemon is not reachable through /var/run/docker.sock."
    exit 1
  fi
  echo "Using host Docker (socket mounted)."
  echo "NOTE: Host Docker cleanup only removes resources labeled runner-owner=${NAME}."
else
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: DinD mode requires root inside the container. Run with --user 0:0 or set HOSTDOCKER=1."
    exit 1
  fi
  if ! start_dind; then
    echo "ERROR: DinD startup failed. Ensure the container is running with --privileged."
    exit 1
  fi
fi
cleanup_docker_resources

# -- Configure & run ------------------------------------------------------
if [[ "${_runner_configured}" != "true" ]]; then
  REG_TOKEN="$(fetch_registration_token)"
  configure_runner "${REG_TOKEN}"
fi

runner_attempt=0
while true; do
  echo "Starting runner..."
  ./run.sh &
  _runner_pid=$!
  runner_exit=0
  wait "${_runner_pid}" || runner_exit=$?
  _runner_pid=""
  echo "Runner process exited with status ${runner_exit}."

  if [[ "${runner_exit}" -eq 0 ]]; then
    exit 0
  fi
  if (( runner_attempt >= RUNNER_SESSION_RETRIES )); then
    echo "ERROR: Runner failed after $((runner_attempt + 1)) attempt(s); giving up."
    exit "${runner_exit}"
  fi

  runner_attempt=$((runner_attempt + 1))
  retry_delay=$((runner_attempt * 5))
  echo "WARN: Runner session failed; re-registering in ${retry_delay}s (retry ${runner_attempt}/${RUNNER_SESSION_RETRIES})..."
  sleep "${retry_delay}"
  clear_local_runner_config
  _runner_configured="false"
  REG_TOKEN="$(fetch_registration_token)"
  configure_runner "${REG_TOKEN}"
done
