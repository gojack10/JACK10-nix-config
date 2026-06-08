{ config, pkgs, lib, hostname, ... }:

let
  home = config.home.homeDirectory;
  enabled = hostname == "m5-max";
  localConfig = "${home}/.config/JACK10-nix-config/local/ssh.env";
  logFile = "${home}/Library/Logs/reverse-ssh-tunnel.log";
  errLogFile = "${home}/Library/Logs/reverse-ssh-tunnel.err.log";
  launcher = pkgs.writeShellScript "reverse-ssh-tunnel-launch" ''
    set -eu

    local_config=${lib.escapeShellArg localConfig}

    log() {
      printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
    }

    if [ ! -f "$local_config" ]; then
      log "reverse SSH tunnel is not configured."
      log "Create $local_config with local-only settings."
      log "Required: JACK10_REVERSE_SSH_TUNNEL_TARGET or JACK10_SSH_TARGET."
      log "Required: JACK10_REVERSE_SSH_TUNNEL_REMOTE_FORWARDS."
      log "Optional: JACK10_REVERSE_SSH_TUNNEL_PORT or JACK10_SSH_PORT. Prefer ~/.ssh/config."
      exit 78
    fi

    # shellcheck disable=SC1090
    . "$local_config"

    tunnel_target="''${JACK10_REVERSE_SSH_TUNNEL_TARGET:-''${JACK10_SSH_TARGET:-}}"
    tunnel_port="''${JACK10_REVERSE_SSH_TUNNEL_PORT:-''${JACK10_SSH_PORT:-}}"
    tunnel_remote_forwards="''${JACK10_REVERSE_SSH_TUNNEL_REMOTE_FORWARDS:-}"

    if [ -z "$tunnel_target" ]; then
      log "reverse SSH tunnel config is missing JACK10_REVERSE_SSH_TUNNEL_TARGET or JACK10_SSH_TARGET in $local_config."
      exit 78
    fi

    if [ -z "$tunnel_remote_forwards" ]; then
      log "reverse SSH tunnel config is missing JACK10_REVERSE_SSH_TUNNEL_REMOTE_FORWARDS in $local_config."
      exit 78
    fi

    set -- ${pkgs.autossh}/bin/autossh \
      -M 0 \
      -N \
      -T \
      -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=30 \
      -o ServerAliveCountMax=3 \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=10

    if [ -n "$tunnel_port" ]; then
      set -- "$@" -p "$tunnel_port"
    fi

    # Intentionally split on whitespace: each item must be one ssh -R spec.
    for forward in $tunnel_remote_forwards; do
      set -- "$@" -R "$forward"
    done

    exec "$@" "$tunnel_target"
  '';
in {
  home.activation.warn-reverse-ssh-tunnel = lib.mkIf enabled (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${lib.escapeShellArg home}/.config/JACK10-nix-config/local ${lib.escapeShellArg home}/Library/Logs

    if [ -f ${lib.escapeShellArg localConfig} ]; then
      chmod 600 ${lib.escapeShellArg localConfig} || true
    fi

    if [ ! -f ${lib.escapeShellArg localConfig} ] \
      || { ! grep -Eq '^[[:space:]]*JACK10_REVERSE_SSH_TUNNEL_TARGET=' ${lib.escapeShellArg localConfig} && ! grep -Eq '^[[:space:]]*JACK10_SSH_TARGET=' ${lib.escapeShellArg localConfig}; } \
      || ! grep -Eq '^[[:space:]]*JACK10_REVERSE_SSH_TUNNEL_REMOTE_FORWARDS=' ${lib.escapeShellArg localConfig}; then
      cat >&2 <<'EOF'
warning: reverse SSH tunnel launchagent is installed but not configured.
Create this local, gitignored env file:

  ~/.config/JACK10-nix-config/local/ssh.env

Suggested shape:

  JACK10_SSH_TARGET=my-ssh-config-host-alias
  JACK10_REVERSE_SSH_TUNNEL_REMOTE_FORWARDS='remote_port:localhost:local_port remote_port:localhost:local_port'
  # Optional if not already in ~/.ssh/config:
  # JACK10_SSH_PORT=22

Prefer storing host/user/port in ~/.ssh/config under the alias above.
EOF
      cat > ${lib.escapeShellArg errLogFile} <<'EOF'
reverse SSH tunnel launchagent is installed but not configured.
Create ~/.config/JACK10-nix-config/local/ssh.env with:

  JACK10_SSH_TARGET=my-ssh-config-host-alias
  JACK10_REVERSE_SSH_TUNNEL_REMOTE_FORWARDS='remote_port:localhost:local_port remote_port:localhost:local_port'
  # Optional: JACK10_SSH_PORT=22

No hostnames, usernames, or private ports should be committed to git.
EOF
    fi
  '');

  launchd.agents.reverse-ssh-tunnel = lib.mkIf enabled {
    enable = true;
    config = {
      Label = "com.jack.reverse-ssh-tunnel";
      ProgramArguments = [ "${launcher}" ];
      WorkingDirectory = home;
      EnvironmentVariables = {
        HOME = home;
        PATH = "${pkgs.autossh}/bin:${pkgs.openssh}/bin:/usr/bin:/bin";
        AUTOSSH_GATETIME = "0";
      };
      StandardOutPath = logFile;
      StandardErrorPath = errLogFile;
      RunAtLoad = true;
      KeepAlive = {
        NetworkState = true;
        SuccessfulExit = false;
      };
      ThrottleInterval = 60;
    };
  };
}
