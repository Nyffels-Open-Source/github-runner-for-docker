# GitHub Actions Runner for Docker

Run an ephemeral GitHub Actions organization runner in a Docker container. The image starts Docker-in-Docker by default and can also use a host Docker socket when explicitly configured.

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
```

`--privileged` and `--user 0:0` are required for Docker-in-Docker mode so the container can start Docker daemon internals. They are not normally required for host-socket mode unless the host socket permissions require them.

Mounting `/var/run/docker.sock` effectively grants root-equivalent access to the host. Use dedicated runner hosts and restrict who can run jobs on these labels.

## Configuration

| Variable | Required | Default | Description |
|---|---:|---|---|
| `ORG` | Yes | | GitHub organization name. |
| `PAT` | Yes | | Token with permission to create organization runner registration and removal tokens. |
| `NAME` | No | `<hostname>-ephemeral` | Runner name registered in GitHub. |
| `HOSTDOCKER` | No | `0` | Set to `1`, `true`, `yes`, or `on` to use the mounted host Docker socket. |
| `LABELS` | No | | Extra comma-separated or semicolon-separated runner labels. |
| `LABEL_MODE` | No | `append` | Use `append` to add `LABELS` to defaults or `replace` to use only `LABELS`. |
| `RUNNER_WORK_DIRECTORY` | No | `_work` | Runner work directory under `/actions-runner`. |
| `DOCKER_DRIVER` | No | `overlay2` | Docker-in-Docker storage driver. Falls back to `vfs` if startup fails. |
| `DOCKER_DATA_ROOT` | No | `/var/lib/docker` | Docker-in-Docker data root. |
| `DOCKERD_ARGS` | No | | Extra flags passed to `dockerd`. |

Default runner labels are `ephemeral,docker,self-hosted`. GitHub also applies its own OS and architecture labels for the runner binary.

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

The runner is registered as ephemeral and removed on container shutdown when possible. In host Docker socket mode, cleanup only removes containers and images labeled with `runner-owner=<NAME>`. Label job-created Docker resources if you want the cleanup pass to remove them.

## License

MIT. See [LICENSE](LICENSE).
