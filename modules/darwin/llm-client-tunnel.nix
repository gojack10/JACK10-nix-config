{ config, pkgs, lib, hostname, ... }:

let
  home = config.home.homeDirectory;
  # Every Darwin host except the engine host is a client: it consumes the
  # engine host's proxy instead of serving one, and publishes its own sshd
  # for maintenance. Target, port and forward specs stay in a local gitignored
  # file; no hostnames, usernames or private ports belong in this repository.
  enabled = hostname != "m5-max";
  localConfig = "${home}/.config/JACK10-nix-config/local/ssh.env";
  logFile = "${home}/Library/Logs/llm-client-tunnel.log";
  errLogFile = "${home}/Library/Logs/llm-client-tunnel.err.log";
  launcher = pkgs.writeShellScript "llm-client-tunnel-launch" ''
    set -eu

    local_config=${lib.escapeShellArg localConfig}

    log() {
      printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
    }

    if [ ! -f "$local_config" ]; then
      log "llm client tunnel is not configured: create $local_config with" \
        "JACK10_SSH_TARGET and JACK10_LLM_CLIENT_{REMOTE,LOCAL}_FORWARDS."
      exit 78
    fi

    # shellcheck disable=SC1090
    . "$local_config"

    tunnel_target="''${JACK10_REVERSE_SSH_TUNNEL_TARGET:-''${JACK10_SSH_TARGET:-}}"
    tunnel_port="''${JACK10_REVERSE_SSH_TUNNEL_PORT:-''${JACK10_SSH_PORT:-}}"
    remote_forwards="''${JACK10_LLM_CLIENT_REMOTE_FORWARDS:-}"
    local_forwards="''${JACK10_LLM_CLIENT_LOCAL_FORWARDS:-}"
    tunnel_key="''${JACK10_LLM_CLIENT_SSH_KEY:-}"

    if [ -z "$tunnel_target" ]; then
      log "llm client tunnel is missing JACK10_SSH_TARGET in $local_config."
      exit 78
    fi

    if [ -z "$remote_forwards" ] && [ -z "$local_forwards" ]; then
      log "llm client tunnel has no forwards to set up."
      exit 78
    fi

    # Default: whatever identity this machine already uses for the target, from
    # ~/.ssh/config or the agent. JACK10_LLM_CLIENT_SSH_KEY pins a dedicated key
    # for a host that has no working identity of its own.
    if [ -n "$tunnel_key" ] && [ ! -f "$tunnel_key" ]; then
      log "JACK10_LLM_CLIENT_SSH_KEY points at a missing key: $tunnel_key"
      exit 78
    fi

    set -- ${pkgs.autossh}/bin/autossh \
      -M 0 \
      -N \
      -T \
      -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=15 \
      -o ServerAliveCountMax=2 \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=10

    if [ -n "$tunnel_key" ]; then
      set -- "$@" -o IdentitiesOnly=yes -i "$tunnel_key"
    fi

    if [ -n "$tunnel_port" ]; then
      set -- "$@" -p "$tunnel_port"
    fi

    # Intentionally split on whitespace: each item must be one ssh forward spec.
    for forward in $remote_forwards; do
      set -- "$@" -R "$forward"
    done
    for forward in $local_forwards; do
      set -- "$@" -L "$forward"
    done

    exec "$@" "$tunnel_target"
  '';
in {
  home.activation.warn-llm-client-tunnel = lib.mkIf enabled (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${lib.escapeShellArg home}/.config/JACK10-nix-config/local ${lib.escapeShellArg home}/Library/Logs

    if [ -f ${lib.escapeShellArg localConfig} ]; then
      chmod 600 ${lib.escapeShellArg localConfig} || true
    fi

    if [ ! -f ${lib.escapeShellArg localConfig} ] \
      || ! grep -Eq '^[[:space:]]*(JACK10_REVERSE_SSH_TUNNEL_TARGET|JACK10_SSH_TARGET)=' ${lib.escapeShellArg localConfig} \
      || ! grep -Eq '^[[:space:]]*JACK10_LLM_CLIENT_(REMOTE|LOCAL)_FORWARDS=' ${lib.escapeShellArg localConfig}; then
      cat >&2 <<'EOF'
warning: llm client tunnel launchagent is installed but not configured.
Create this local, gitignored env file:

  ~/.config/JACK10-nix-config/local/ssh.env

Suggested shape (values are per-machine, never committed):

  JACK10_SSH_TARGET=my-ssh-config-host-alias
  # A loopback port on the target for this machine's own sshd, and the target's
  # loopback port that already reaches the engine host's local LLM proxy:
  JACK10_LLM_CLIENT_REMOTE_FORWARDS='remote_port:localhost:22'
  JACK10_LLM_CLIENT_LOCAL_FORWARDS='local_port:localhost:remote_port'
  # Optional if not already in ~/.ssh/config:
  # JACK10_SSH_PORT=22
  # Optional, only when the machine has no working identity for the target:
  # JACK10_LLM_CLIENT_SSH_KEY=~/.ssh/id_ed25519

No hostnames, usernames, or private ports should be committed to git.
EOF
      cat > ${lib.escapeShellArg errLogFile} <<'EOF'
llm client tunnel launchagent is installed but not configured.
Create ~/.config/JACK10-nix-config/local/ssh.env with JACK10_SSH_TARGET and
JACK10_LLM_CLIENT_REMOTE_FORWARDS / JACK10_LLM_CLIENT_LOCAL_FORWARDS.
EOF
    fi
  '');

  launchd.agents.llm-client-tunnel = lib.mkIf enabled {
    enable = true;
    config = {
      Label = "com.jack.llm-client-tunnel";
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
