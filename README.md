# SuperDocker.sh
A Bash profile script to make your Docker+SSH life easier


### Features
* Automatically imports new Docker SSH context Hostnames from your ~/.ssh/config
* Automatically forwards ports specified on the command line to your local machine
* Responsive, using sockets for Docker and port forwarding connections
* Automatic switch to using the newer docker buildx utility when using "docker build"
* Minimalistic operation (does not add new syntax, only makes the existing features more convienent)
* Configurable parameters in the script


### Installation
First, edit the script, and ensure all required utilities are installed, and that the paths to all utilites match those in your system. Then, simply copy and paste, or append superdocker.sh to your ~/.bash_profile or ~/.bashrc, depending on your system. The docker() function in your profile should now override your $PATH to docker, and you should be able to use "docker" like normal.

```
$ cat superdocker.sh >> ~/.bash_profile
$ source .bash_profile
```

### Usage:
#### Using the docker server of another machine configured in your ssh config:
```
docker context use mysshmachine
```

#### Automatically forwarding ports (example)
```
docker run --rm --it <myimage> -p 8888:8080
```
* You can then access the service on port 8080 of your local machine, as you would on the remote machine
