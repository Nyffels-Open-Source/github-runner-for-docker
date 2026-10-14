#!/bin/bash
set -euo pipefail
cd /actions-runner
mock_directory="$(mktemp -d)"
export PATH="${mock_directory}:${PATH}"
export TEST_LOG="${mock_directory}/calls"
export PAT=test-token ORG=test-org NAME=test-runner
export DOCKER_HOST=tcp://wrong-daemon:2375 DOCKER_CONTEXT=wrong-context
export RUNNER_SESSION_RETRIES=1

cat > "${mock_directory}/curl" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "${*: -1}" in
  'https://api.github.com/') printf 'HTTP/1.1 200 OK\r\n\r\n' ;;
  *'/registration-token') printf '{"token":"registration-token"}' ;;
  *'/remove-token') printf '{"token":"remove-token"}' ;;
  *'/actions/runners?'*)
    if [[ "${TEST_ONLINE:-0}" == 1 ]]; then
      printf '{"runners":[{"name":"test-runner","id":1,"status":"online","busy":false}]}'
    else
      printf '{"runners":[{"name":"test-runner","id":1,"status":"offline","busy":false}]}'
    fi ;;
  *'/actions/runners/1') echo deleted >> "$TEST_LOG" ;;
  *) exit 1 ;;
esac
MOCK
cat > "${mock_directory}/docker" <<'MOCK'
#!/bin/bash
set -euo pipefail
[[ "$DOCKER_HOST" == unix:///var/run/docker.sock ]]
[[ -z "${DOCKER_CONTEXT:-}" && -z "${PAT:-}" ]]
printf 'docker %s\n' "$*" >> "$TEST_LOG"
MOCK
cat > "${mock_directory}/dockerd" <<'MOCK'
#!/bin/bash
exec sleep 300
MOCK
cat > config.sh <<'MOCK'
#!/bin/bash
set -euo pipefail
[[ -z "${PAT:-}" ]]
if [[ "${1:-}" == remove ]]; then
  echo removed >> "$TEST_LOG"
  rm -f .runner
else
  echo configured >> "$TEST_LOG"
  touch .runner
fi
MOCK
cat > bin/Runner.Listener <<'MOCK'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
  echo "$RUNNER_VERSION"
  exit
fi
[[ -z "${PAT:-}" ]]
echo listener >> "$TEST_LOG"
if [[ "${TEST_RETRY:-0}" == 1 && ! -f "${TEST_LOG}.retried" ]]; then
  touch "${TEST_LOG}.retried"
  exit 1
fi
MOCK
chmod +x "${mock_directory}"/* config.sh bin/Runner.Listener

expect_failure() {
  local expected="$1"
  shift
  if env "$@" bash /entrypoint.sh > "${mock_directory}/output" 2>&1; then
    echo "Expected failure: $*"
    exit 1
  fi
  grep -q "$expected" "${mock_directory}/output"
}

for work in . _work/.. ../escape /tmp/work bin externals/node24; do
  expect_failure 'ERROR: RUNNER_WORK_DIRECTORY' "RUNNER_WORK_DIRECTORY=${work}"
done
ln -s /tmp workspace-link
expect_failure 'ERROR: RUNNER_WORK_DIRECTORY' RUNNER_WORK_DIRECTORY=workspace-link
expect_failure 'ERROR: ORG' ORG=owner/repo
expect_failure 'ERROR: REPO' REPO=owner/repo
expect_failure 'ERROR: A live runner' TEST_ONLINE=1
if [[ -s "$TEST_LOG" ]]; then exit 1; fi

node -e 'require("net").createServer().listen("/var/run/docker.sock")' &
socket_pid=$!
for _ in {1..50}; do
  [[ -S /var/run/docker.sock ]] && break
  sleep 0.1
done
expect_failure 'ERROR: An existing Docker daemon' HOSTDOCKER=0
if grep -q '^docker system prune' "$TEST_LOG"; then exit 1; fi
kill "$socket_pid"
wait "$socket_pid" || true
rm -f /var/run/docker.sock
: > "$TEST_LOG"

printf '%s' test-token > "${mock_directory}/pat"
PAT='' PAT_FILE="${mock_directory}/pat" bash /entrypoint.sh > "${mock_directory}/output" 2>&1
[[ "$(grep -c '^configured$' "$TEST_LOG")" == 1 ]]
grep -q '^deleted$' "$TEST_LOG"
grep -q '^removed$' "$TEST_LOG"
grep -q '^docker system prune' "$TEST_LOG"

: > "$TEST_LOG"
TEST_RETRY=1 bash /entrypoint.sh > "${mock_directory}/output" 2>&1
[[ "$(grep -c '^configured$' "$TEST_LOG")" == 2 ]]
[[ "$(grep -c '^listener$' "$TEST_LOG")" == 2 ]]
[[ "$(grep -c '^removed$' "$TEST_LOG")" == 2 ]]

: > "$TEST_LOG"
RUNNER_CLEANUP_DOCKER=0 bash /entrypoint.sh > "${mock_directory}/output" 2>&1
if grep -q '^docker system prune' "$TEST_LOG"; then exit 1; fi

echo 'Entrypoint safety and lifecycle tests passed.'
