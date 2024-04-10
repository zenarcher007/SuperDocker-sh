# SuperDocker
#   

#MIT License

#Copyright (c) 2024 Justin Douty

#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.


# A wrapper function to more efficiently add and manage contexts and enhance building
# Automatically adds new contexts for any Host names defined in your ~/.ssh/config
# Creates persistent sockets for new connections (which may exit upon network loss
# and be restablished at next context invocation), to improve response time vs opening
# new SSH connections each time.
# Works well when placed inside your ~/.bash_profile or ~/.bashrc
function docker() {
  # Settings:
  DOCKER_PATH="/opt/homebrew/bin/docker"
  
  # May set this to ".../docker buildx" if this is how this is invoked on your system.
  # Set to "" to disable automatic alias to newer buildx builder
  DOCKER_BUILDX_PATH="/opt/homebrew/bin/docker-buildx"
  
  SOCAT_PATH="/opt/homebrew/bin/socat"
  GREP_PATH="/opt/homebrew/bin/ggrep"
  #_.-^-._.-^-._.-^-._.-^-._

  SOCKET_DIR="/tmp/.docker"
  if ! [[ -d "$SOCKET_DIR" ]]; then
    mkdir "$SOCKET_DIR"
  fi
  cmd="$DOCKER_PATH"
  if [[ "$1" == "build" ]]; then
    if ! [[ -z "DOCKER_BUILDX_PATH" ]]; then
      cmd="$DOCKER_BUILDX_PATH"
    fi
  elif [[ "$1" == "context" ]]; then
    if [[ "$2" == "use" ]] && ! [[ -z "$3" ]]; then
      unset DOCKER_HOST
      reqHost="$3"
      #export DOCKER_HOST="unix://$SOCKET_DIR/$reqHost.sock"
      # If the context does not exist
      if ! "$cmd" context ls -q | grep "$reqHost" &>/dev/null; then
        # If the host is present in the ssh config
        if "$GREP_PATH" "Host $reqHost" ~/.ssh/config &>/dev/null; then
          # Create a new context
          "$cmd" context create "$reqHost" --docker "host=unix://$SOCKET_DIR/$reqHost.sock"
        fi
      fi

      # Create control master connection, which will be used throughout this context
      ssh -N -f -oControlMaster=auto -oControlPath="$SOCKET_DIR/$reqHost_CONTROL_MASTER.sock" -oControlPersist=2m "$reqHost"

      ### This works by creating a remote Docker socket, and telling Docker to point to it. ###
      # If the Docker socket does not exist, is accessible, and a process is listening
      # socat will exit uncleanly if any one of these are false.
      # Check for existence because it will also exit uncleanly if the command doesn't exist
      if ! which "$SOCAT_PATH" &>/dev/null; then
        echo ERROR: socat command is missing && return 1
      fi
      if ! "$SOCAT_PATH" -u OPEN:/dev/null "UNIX-CONNECT:$SOCKET_DIR/$reqHost.sock" &>/dev/null; then
        # [[ -e "$SOCKET_DIR/$reqHost.sock" ]]
        ssh -f -o "ServerAliveInterval 60" -o "ServerAliveCountMax 1" -o "ExitOnForwardFailure yes" -o "StreamLocalBindUnlink yes" -nNT -L "$SOCKET_DIR/$reqHost.sock:/var/run/docker.sock" "$reqHost"
      fi
    fi
  fi

  ### Section: Running the command (and forwarding ports)
  e=""
  ### Forward ports automatically for the duration of an interactive session
  # Note: "-p" is contained in "--publish"
  # Case #1: forward ports and then run command. Case #2: just run the command
  if [[ "$@" == *"-p"* || "$@" == *"--publish"* ]] && [[ "$@" != *"-d"* && "$@" != *"--detach"* ]]; then

    # Extract the last number from all port command line specifications (the remote device port that will be brought locally)
    ports="$("$GREP_PATH" -P -o '(-p|--publish) ([0-9]*:)?[0-9]*' <<< "$@" | "$GREP_PATH" -P -o '(?<=:)?[0-9]*$')"
    echo $ports
    echo -n "Forwarded ports" 1>&2
    forwarded_ports=""
    for port in $ports; do
      if ! nc -z "127.0.0.1" "$port" &>/dev/null; then # Note: netcat is required for this
        if [[ -z "$forwarded_ports" ]]; then forwarded_ports="$port"
        else
          forwarded_ports+=" $port"
        fi
        ssh -oControlPath="$SOCKET_DIR/$reqHost_CONTROL_MASTER.sock" -O forward -L "127.0.0.1:$port:localhost:$port" "$reqHost"
        echo -n " $port" 1>&2
      else
        echo -n " [$port is already bound]"
      fi
    done
    echo 1>&2

    "$cmd" "$@" # Run command
    e="$?"
    
    echo -en "\nUnforwarded ports" 1>&2
    for port in $forwarded_ports; do
      ssh -oControlPath="$SOCKET_DIR/$reqHost_CONTROL_MASTER.sock" -O cancel -L "127.0.0.1:$port:localhost:$port" "$reqHost"
      echo -n " $port" 1>&2
    done
    echo 1>&2
  else
    "$cmd" "$@" # Run command
    e="$?"
  fi

  unset reqHost
  #unset DOCKER_HOST
  unset cmd
  return "$e"
}
