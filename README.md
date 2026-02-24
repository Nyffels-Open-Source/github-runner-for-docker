# Github Action Runner 

Run a Github Actions Runner inside of a docker environment on an organisation level. This docker includes an internal docker instance (DinD) by default. The runner binary is checksum-verified during image build and at runtime, and Docker is installed from the official apt repository.

# Installation 

## CLI example (`docker run`)

```bash
  # Default (DinD): start Docker daemon inside the container
  docker run --privileged --user 0:0 --name github-runner --env=NAME=<NAME> --env=ORG=<ORG> --env=PAT=<PAT> -d nyffels/github-runner:latest

  # Host Docker: use the host daemon via socket mount
  docker run --name github-runner --env=NAME=<NAME> --env=ORG=<ORG> --env=PAT=<PAT> --env=HOSTDOCKER=1 -v /var/run/docker.sock:/var/run/docker.sock -d nyffels/github-runner:latest
```

## Docker Compose example

```yaml
services:
  # DinD mode
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

  # Host Docker mode
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

`--privileged` and `--user 0:0` are required for DinD so the container can start the Docker daemon and access the necessary kernel features. For host-socket mode (`HOSTDOCKER=1`), they are not required unless your Docker socket permissions require elevated access.

Security note: `--privileged` grants broad kernel access inside the container, and mounting `/var/run/docker.sock` effectively grants root access on the host. Prefer DinD for better isolation (with higher resource usage), and if you use the host socket, run on dedicated hosts with restricted access.

# Environments 

NAME = Name of docker runner in github.  
ORG = ID of the organisation in github.  
PAT = Personal access token of your user for requested runner tokens.  
HOSTDOCKER = Set to "1" to use the docker of the host by a volume mount (ex. -v /var/run/docker.sock:/var/run/docker.sock). If set, the container will exit if the socket is missing.  
CLEANUP NOTE = Host Docker cleanup only removes containers/images labeled `runner-owner=<NAME>`. If you want cleanup to be effective, label your job-created containers/images accordingly.  

# Legal information
This image is created by "Nyffels BV" under the MIT license. 

# Contribution
Feel free to branch / fork this repo and make adjustments. To merge in the master branch, please open a issue and a PR in the github repo. 
