# Github Action Runner 

Run a Github Actions Runner inside of a docker environment on an organisation level. This docker includes an internal docker instance. 

# Installation 

```bash
  docker run --privileged --name github-runner --env=NAME=<NAME> --env=ORG=<ORG> --env=PAT=<PAT> -d nyffelsit/github-runner:latest
```

# Environments 

NAME = Name of docker runner in github.  
ORG = ID of the organisation in github.  
PAT = Personal access token of your user for requested runner tokens.  
HOSTDOCKER = Set to "1" to use the docker of the host by a volume mount (ex. -v /var/run/docker.sock:/var/run/docker.sock)  

# Legal information
This image is created by "Nyffels BV" under the MIT license. 

# Contribution
Feel free to branch / fork this repo and make adjustments. To merge in the master branch, please open a issue and a PR in the github repo. 
