# Github Action Runner 

Run a Github Actions Runner inside of a docker environment on an organisation level. This docker includes an internal docker instance (DinD) by default. 

# Installation 

```bash
  # Default (DinD): start Docker daemon inside the container
  docker run --privileged --name github-runner --env=NAME=<NAME> --env=ORG=<ORG> --env=PAT=<PAT> -d nyffels/github-runner:latest

  # Host Docker: use the host daemon via socket mount
  docker run --privileged --name github-runner --env=NAME=<NAME> --env=ORG=<ORG> --env=PAT=<PAT> --env=HOSTDOCKER=1 -v /var/run/docker.sock:/var/run/docker.sock -d nyffels/github-runner:latest
```

`--privileged` is required for DinD so the container can start the Docker daemon and access the necessary kernel features. It is also commonly used with the host socket mount to avoid permission issues, but you can omit it if your environment allows Docker socket access without it.

Security note: `--privileged` grants broad kernel access inside the container, and mounting `/var/run/docker.sock` effectively grants root access on the host. Prefer DinD for better isolation (with higher resource usage), and if you use the host socket, run on dedicated hosts with restricted access.

# Environments 

NAME = Name of docker runner in github.  
ORG = ID of the organisation in github.  
PAT = Personal access token of your user for requested runner tokens.  
HOSTDOCKER = Set to "1" to use the docker of the host by a volume mount (ex. -v /var/run/docker.sock:/var/run/docker.sock). If set, the container will exit if the socket is missing.  

# Legal information
This image is created by "Nyffels BV" under the MIT license. 

# Contribution
Feel free to branch / fork this repo and make adjustments. To merge in the master branch, please open a issue and a PR in the github repo. 
