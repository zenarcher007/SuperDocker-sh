
#!/usr/bin/env bash

#!/usr/bin/env bash

# SuperDocker
#   Justin Douty
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
      
      # If the context does not exist
      if ! "$cmd" context ls -q | grep "$reqHost" &>/dev/null; then
        # If the host is present in the ssh config
        if grep "Host $reqHost" ~/.ssh/config &>/dev/null; then
          # Create a new context
          "$cmd" context create "$reqHost" --docker "host=unix://$SOCKET_DIR/$reqHost.sock"
        fi
      fi

      # If the socket does not exist, is accessible, and a process is listening
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
  unset reqHost
  "$cmd" "$@" # Run command
  e="$?"
  unset cmd
  return "$e"
}