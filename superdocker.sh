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



# SuperDocker
#   Justin Douty
# A wrapper function to more efficiently add and manage contexts and enhance building
# Automatically adds new contexts for any Host names defined in your ~/.ssh/config
# Creates persistent sockets for new connections (which may exit upon network loss
# and be restablished at next context invocation), to improve response time vs opening
# new SSH connections each time.
# Works well when placed inside your ~/.bash_profile or ~/.bashrc
### Be sure to include the superdocker_cleanup function as well!
function docker() {
  # Settings:
  local DOCKER_PATH="/opt/homebrew/bin/docker"
  
  # May set this to ".../docker buildx" if this is how this is invoked on your system.
  # Set to "" to disable automatic alias to newer buildx builder
  local DOCKER_BUILDX_PATH="/opt/homebrew/bin/docker-buildx"
  
  local SOCAT_PATH="/opt/homebrew/bin/socat"
  local GREP_PATH="/opt/homebrew/bin/ggrep"
  local NETCAT_PATH="/usr/bin/nc"
  local PERL_PATH="/usr/bin/perl"
  #_.-^-._.-^-._.-^-._.-^-._

  local SOCKET_DIR="/tmp/.docker"
  if ! [[ -d "$SOCKET_DIR" ]]; then
    mkdir "$SOCKET_DIR"
  fi
  local cmd="$DOCKER_PATH"
  local reqHost=""
  if [[ "$1" == "build" ]]; then
    if ! [[ -z "DOCKER_BUILDX_PATH" ]]; then
      cmd="$DOCKER_BUILDX_PATH"
    fi
  elif [[ "$1" == "context" ]]; then
    if [[ "$2" == "use" ]] && ! [[ -z "$3" ]]; then
      unset DOCKER_HOST
      reqHost="$3"
      #export DOCKER_HOST="unix://$SOCKET_DIR/$reqHost.sock"
      # If the host is present in the ssh config
      if "$GREP_PATH" "Host $reqHost" ~/.ssh/config &>/dev/null; then
        SD_CURRENT_SSH_HOST="$reqHost"
        # If the context does not exist
        if ! "$cmd" context ls -q | grep "$reqHost" &>/dev/null; then
          # Create a new context
          "$cmd" context create "$reqHost" --docker "host=unix://$SOCKET_DIR/$reqHost.sock"
        fi
      else
        SD_CURRENT_SSH_HOST=""
      fi

      ### This works by creating a remote Docker socket, and telling Docker to point to it. ###
      # Checks if the Docker socket does not exist, is accessible, and a process is listening
      # socat will exit uncleanly if any one of these are false.
      # We must check for existence, however, because it will also exit uncleanly if the command doesn't exist
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
  local e=""
  ### Forward ports automatically for the duration of an interactive session
  # Note: "-p" is contained in "--publish"
  # Case #1: forward ports and then run command. Case #2: just run the command

  # Extract the last number from all port command line specifications (the remote device port that will be brought locally)
  local ports="$("$GREP_PATH" -P -o '(-p|--publish) ([0-9]*:)?[0-9]*' <<< "$@" | "$GREP_PATH" -P -o '(?<=:)?[0-9]*$')"
  # [[ "$@" == *"-p"* || "$@" == *"--publish"* ]] &&
  # && "$@" =~ ^.*-it.*|.*-ti.*|.*-i .*-t | .*-i .*-t$ 
  if ! [[ -z "$SD_CURRENT_SSH_HOST" ]] && [[ "$(cut -d ' ' -f1 <<< "$@")" == *"run"* && ! -z "$ports" && "$@" != *"-d"* && "$@" != *"--detach"* ]]; then

    # Create control master connection
    ssh -N -f -oControlMaster=auto -oControlPath="$SOCKET_DIR/${SD_CURRENT_SSH_HOST}_CONTROL_MASTER.sock" -oControlPersist=2m "$SD_CURRENT_SSH_HOST"

    echo -n "Forwarded ports" 1>&2
    local forwarded_ports_local=""
    local forwarded_ports_remote=""
    for port in $ports; do
      # If the port is not already bound, forward it as a "local" port. Otherwise, forward it as a "remote" port
      # In simplified terms,
      # local - making a connection to a (newly) listening port on your local machine will make a query to the remote program
      # remote - a query made by the remote program will make a query to an (already) listening program's port on your local machine
      
      local show_remote_warning="false"
      if ! "$NETCAT_PATH" -z "127.0.0.1" "$port" &>/dev/null; then
        ssh -oControlPath="$SOCKET_DIR/${SD_CURRENT_SSH_HOST}_CONTROL_MASTER.sock" -O forward -L "127.0.0.1:$port:localhost:$port" "$SD_CURRENT_SSH_HOST"
        # Add port to list of successfully forwarded ports
        [[ -z "$forwarded_ports_local" ]] && forwarded_ports_local="$port" || forwarded_ports_local+=" $port"
        echo -n ", $port (LOCAL)" 1>&2
      else # If the port is already bound on your local machine, assume you want to recieve connections from the remote program instead
        # old behavior: echo -n " [$port is already bound]"
        ssh -oControlPath="$SOCKET_DIR/${SD_CURRENT_SSH_HOST}_CONTROL_MASTER.sock" -O forward -R "127.0.0.1:$port:localhost:$port" "$SD_CURRENT_SSH_HOST"
        [[ -z "$forwarded_ports_remote" ]] && forwarded_ports_remote="$port" || forwarded_ports_remote+=" $port"
        echo -n ", $port (REMOTE)" 1>&2
        show_remote_warning="true"
      fi
    done
    echo 1>&2 # Newline
    [[ "$show_remote_warning" == "true" ]] && echo "  (Note: ports forwarded as REMOTE were already in use locally)" 1>&2

    "$cmd" "$@" # Run command
    e="$?"

    echo -en "Unforwarded ports" 1>&2
    for port in $forwarded_ports_local; do
      ssh -oControlPath="$SOCKET_DIR/${SD_CURRENT_SSH_HOST}_CONTROL_MASTER.sock" -O cancel -L "127.0.0.1:$port:localhost:$port" "$SD_CURRENT_SSH_HOST"
      echo -n ", $port (LOCAL)" 1>&2
    done
    for port in $forwarded_ports_remote; do
      ssh -oControlPath="$SOCKET_DIR/${SD_CURRENT_SSH_HOST}_CONTROL_MASTER.sock" -O cancel -R "127.0.0.1:$port:localhost:$port" "$SD_CURRENT_SSH_HOST"
      echo -n ", $port (REMOTE)" 1>&2
    done
    echo 1>&2
  else
    "$cmd" "$@" # Run command
    e="$?"
  fi

  
  return "$e"
}
