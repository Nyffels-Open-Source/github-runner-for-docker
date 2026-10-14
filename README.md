# GitHub Actions Runner for Docker

Run an ephemeral GitHub Actions runner for an organization or a single repository in a Docker container. Set `REPO` to target one repository within `ORG`; omit it to register an organization-wide runner. The image starts Docker-in-Docker by default and can also use a host Docker socket when explicitly configured.

The image uses Ubuntu 26.04 LTS and pins the runner version at build time. Current defaults are runner 2.338.0, Node.js 24.21.0 LTS, and npm 12.2.0. Node.js and npm are installed on `PATH` for shell jobs; GitHub's bundled action runtimes are preserved unchanged. Runner self-updates are disabled inside the container; rebuild the image regularly to pick up runner, operating-system, Node.js, npm, and Docker security updates.

## Platform Support

This project builds Linux runner images for:

| Image platform | Typical hosts |
|---|---|
| `linux/amd64` | Linux x64, Windows Docker Desktop/WSL2 on x64 |
| `linux/arm64` | Linux ARM64, macOS Apple Silicon Docker Desktop, Windows Docker Desktop/WSL2 on ARM64 |

The container is still a Linux runner. It can run on Docker Desktop for macOS or Windows, but jobs that require native `runs-on: macos-*` or `runs-on: windows-*` need separate self-hosted runners installed directly on macOS or Windows hosts.

## Run

### Docker CLI

```bash
# Docker-in-Docker mode
docker run --privileged --restart unless-stopped --user 0:0 \
  --name github-runner \
  --env NAME=<NAME> \
  --env ORG=<ORG> \
  --env PAT=<PAT> \
  -d nyffels/github-runner:latest

# Host Docker socket mode
docker run --restart unless-stopped \
  --name github-runner \
  --env NAME=<NAME> \
  --env ORG=<ORG> \
  --env PAT=<PAT> \
  --env HOSTDOCKER=1 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -d nyffels/github-runner:latest

# Single-repository runner (Docker-in-Docker mode)
docker run --privileged --restart unless-stopped --user 0:0 \
  --name github-runner-repo \
  --env NAME=<NAME> \
  --env ORG=<ORG> \
  --env REPO=<REPO> \
  --env PAT=<PAT> \
  -d nyffels/github-runner:latest
```

### Docker Compose

```yaml
services:
  runner-dind:
    image: nyffels/github-runner:latest
    container_name: github-runner-dind
    privileged: true
    user: "0:0"
    restart: unless-stopped
    environment:
      NAME: "runner-dind"
      ORG: "${ORG}"
      PAT: "${PAT}"

  runner-host:
    image: nyffels/github-runner:latest
    container_name: github-runner-host
    restart: unless-stopped
    environment:
      NAME: "runner-host"
      ORG: "${ORG}"
      PAT: "${PAT}"
      HOSTDOCKER: "1"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

  runner-repo:
    image: nyffels/github-runner:latest
    container_name: github-runner-repo
    privileged: true
    user: "0:0"
    restart: unless-stopped
    environment:
      NAME: "runner-repo"
      ORG: "${ORG}"
      REPO: "${REPO}"
      PAT: "${PAT}"
```

`--privileged` and `--user 0:0` are required for Docker-in-Docker mode so the container can start Docker daemon internals. They are not normally required for host-socket mode unless the host socket permissions require them.

Mounting `/var/run/docker.sock` effectively grants root-equivalent access to the host. Use dedicated runner hosts and restrict who can run jobs on these labels.

## Configuration

| Variable | Required | Default | Description |
|---|---:|---|---|
| `ORG` | Yes | | GitHub organization name. |
| `REPO` | No | | Repository name within `ORG`. When set, registers the runner only for that repository; do not include `ORG/` or a slash. |
| `PAT` | Unless `PAT_FILE` is set | | Token permitted to manage self-hosted runners in the selected organization or repository scope. |
| `PAT_FILE` | No | | Read the token from a mounted secret file instead of `PAT`. Set only one of these variables. |
| `NAME` | No | `<hostname>-ephemeral` | Runner name registered in GitHub. |
| `HOSTDOCKER` | No | `0` | Set to `1`, `true`, `yes`, or `on` to use the mounted host Docker socket. |
| `LABELS` | No | | Extra comma-separated or semicolon-separated runner labels. |
| `LABEL_MODE` | No | `append` | Use `append` to add `LABELS` to defaults or `replace` to use only `LABELS`. |
| `RUNNER_WORK_DIRECTORY` | No | `_work` | Runner work directory under `/actions-runner`. |
| `DOCKER_DRIVER` | No | `overlay2` | Docker-in-Docker storage driver. Falls back to `vfs` if startup fails. |
| `DOCKER_DATA_ROOT` | No | `/var/lib/docker` | Docker-in-Docker data root. |
| `DOCKERD_ARGS` | No | | Extra flags passed to `dockerd`. |
| `RUNNER_SESSION_RETRIES` | No | `3` | Number of times to re-register after the runner exits with an error before the container exits. |
| `RUNNER_CLEANUP_DOCKER` | No | `1` | Remove all containers, images, volumes, networks, and build cache from the private Docker-in-Docker daemon after each job. |
| `RUNNER_MAX_CLOCK_SKEW` | No | `60` | Maximum allowed clock difference from GitHub, in seconds. Startup stops before registration when the host clock exceeds this limit. |

Default runner labels are `ephemeral,docker,self-hosted`. GitHub also applies its own OS and architecture labels for the runner binary.

When `REPO` is omitted, the PAT must be permitted to manage organization runners. When it is set, the PAT must be permitted to manage self-hosted runners for that repository. Keep the token scoped to the selected organization or repository and grant only the GitHub Actions administration rights needed to create registration/removal tokens and manage stale runner registrations.

## Build

Local single-platform build:

```bash
docker build -t github-runner .
```

Multi-platform build for Linux x64 and ARM64:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --pull \
  -t nyffels/github-runner:latest \
  --push .
```

The default image installs Docker Engine, Docker CLI, containerd, and the Docker Buildx and Compose plugins so runner jobs can use commands such as `docker buildx` and `docker compose`.

You can exclude the plugins when building a specialized image:

```bash
docker build --build-arg INSTALL_DOCKER_PLUGINS=false -t github-runner .
```

The plugins can carry Go module findings before Docker publishes rebuilt plugin binaries. Use the opt-out build argument only if you do not run jobs that need Buildx or Compose inside the runner.

## Cleanup

The runner is registered as ephemeral and removed on container shutdown when possible. The workspace, hosted tool cache, and root user NuGet, npm, and application caches are cleaned both at startup and shutdown, so a hard crash cannot leave the next job with data from the previous workspace. The private Docker-in-Docker daemon is also pruned at startup and after every run unless `RUNNER_CLEANUP_DOCKER=0`.

Docker-in-Docker stores images, layers, volumes, and build cache under `/var/lib/docker`. Bind-mount that path to storage outside the host engine's container image when jobs may produce substantial Docker data. The cleanup pass empties it after a normal run and again at startup after an unclean stop.

After a container-engine or host crash, startup removes offline GitHub runner registrations that exactly match `NAME`, clears the local registration files, and registers a fresh ephemeral runner. This avoids trying to recover a server registration that GitHub has already invalidated. If GitHub invalidates a new registration before the runner creates its session, the container prints the relevant runner diagnostics and re-registers up to `RUNNER_SESSION_RETRIES` times.

Use a unique `NAME` for every concurrently running container. Startup refuses to delete an online or busy runner with the same name. GitHub can take time to mark a crashed runner offline; wait for that status before restarting it. Use a unique name per container to avoid registration races.

In host Docker socket mode, cleanup only removes containers and images labeled with `runner-owner=<NAME>`. A shared host daemon cannot safely be pruned globally because it may contain resources belonging to other workloads. Label job-created Docker resources if you want the cleanup pass to remove them.

For a security-grade clean environment, run one container per job and have an external supervisor remove and recreate the container after it exits. Docker restart policies restart the same writable container filesystem, so no script inside that container can guarantee removal of arbitrary files or modifications made outside the workspace. Privileged Docker-in-Docker and host-socket access both give jobs extensive host privileges. Run untrusted jobs on isolated, disposable hosts or virtual machines, restrict runner groups to trusted repositories, and do not share a host with production workloads.

## Updates and validation

Pull requests run ShellCheck, Actionlint, native AMD64/ARM64 builds, tool-version checks, and isolated lifecycle tests. The tests mock GitHub and Docker commands and never register a real runner.

Releases run on pushes to `main`, manual dispatches on `main`, and every Tuesday at 03:30 UTC. The release resolves the latest stable GitHub runner and rebuilds without a layer cache to refresh Ubuntu and Docker packages. It builds on native AMD64 and ARM64 hosts, publishes uniquely named candidate images, scans their exact digests with Trivy, and promotes those digests to CalVer and `latest` only after both scans pass. Candidate tags can contain vulnerabilities and are for validation only. Fixable HIGH/CRITICAL findings block promotion; findings without an upstream fix remain visible in the weekly report.

The Monday security workflow scans one resolved `latest` digest on both architectures and stores reports for 30 days. Scanner failures stop report generation and issue closure. Reports cover all severities without blanket CVE exclusions. Automated issue updates target only marked reports created by `github-actions[bot]`.

Dependabot checks GitHub Actions and Docker base-image updates weekly. The Dockerfile runner default and the Node.js, npm, Trivy, Scout, ShellCheck, and Actionlint version pins still need release review and maintenance. GitHub stops assigning jobs when a runner with self-updates disabled is more than 30 days behind an available release; scheduled releases refresh the runner, but a blocked release or an unchanged running container can still fall behind. Deploy a freshly rebuilt image regularly.

Use `PAT_FILE=/run/secrets/github_runner_token` with a read-only mounted secret where possible. The entrypoint removes `PAT` from the child-process environment, but root jobs can still inspect parent processes and mounted files. Moving runner registration to an external supervisor with GitHub App credentials and short-lived registration or JIT tokens is the stronger design.

The Docker CLI always uses `/var/run/docker.sock`; inherited `DOCKER_HOST`, `DOCKER_CONTEXT`, and TLS connection settings are cleared so cleanup cannot target a remote daemon. DinD startup also refuses an already reachable socket unless `HOSTDOCKER=1`, preventing accidental global cleanup of a mounted host daemon. Host-socket container jobs additionally require bind-mount paths to exist at the same absolute location on the host and runner container. Use Docker-in-Docker for container actions and services unless you have configured and verified those shared paths.

Allow enough shutdown time for job cancellation, Docker cleanup, and runner deregistration, for example `--stop-timeout 120` or Compose `stop_grace_period: 2m`. A forced kill skips cleanup. Forward `/actions-runner/_diag` to external log storage, and have the supervisor replace the entire container after each job when isolation matters.

## License

MIT. See [LICENSE](LICENSE).
