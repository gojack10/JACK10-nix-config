{ config, pkgs, lib, ... }:

{
  home.activation.cloneBrowserHarness =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      jack10_ssh_env="''${JACK10_SSH_ENV:-$HOME/.config/JACK10-nix-config/local/ssh.env}"
      if [ -f "$jack10_ssh_env" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$jack10_ssh_env"
        set +a
      fi

      browser_harness_git_url=""
      browser_harness_ssh_command="${pkgs.openssh}/bin/ssh"

      browser_harness_git_ssh_url() {
        target="$1"
        port="''${2:-}"
        path="$3"
        if [ -n "$port" ]; then
          browser_harness_ssh_command="${pkgs.openssh}/bin/ssh -p $port"
        else
          browser_harness_ssh_command="${pkgs.openssh}/bin/ssh"
        fi

        case "$path" in
          /*)
            if [ -n "$port" ]; then
              browser_harness_git_url="ssh://$target:$port$path"
            else
              browser_harness_git_url="ssh://$target$path"
            fi
            ;;
          *)
            if [ -n "$port" ]; then
              browser_harness_git_url="ssh://$target:$port/$path"
            else
              browser_harness_git_url="$target:$path"
            fi
            ;;
        esac
      }

      browser_harness_resolve_git_url() {
        if [ -n "''${BROWSER_HARNESS_GIT_URL:-}" ]; then
          browser_harness_git_url="$BROWSER_HARNESS_GIT_URL"
          return 0
        fi
        if [ -n "''${JACK10_BROWSER_HARNESS_GIT_URL:-}" ]; then
          browser_harness_git_url="$JACK10_BROWSER_HARNESS_GIT_URL"
          return 0
        fi

        local target target_port target_path
        target="''${BROWSER_HARNESS_SSH_TARGET:-''${JACK10_BROWSER_HARNESS_TARGET:-''${JACK10_SSH_TARGET:-}}}"
        target_port="''${BROWSER_HARNESS_SSH_PORT:-''${JACK10_BROWSER_HARNESS_PORT:-''${JACK10_SSH_PORT:-}}}"
        target_path="''${BROWSER_HARNESS_REPO_PATH:-''${JACK10_BROWSER_HARNESS_REPO_PATH:-git/browser-harness.git}}"
        if [ -n "$target" ]; then
          browser_harness_git_ssh_url "$target" "$target_port" "$target_path"
          return 0
        fi

        local default_user default_port default_path user host port path interactive
        default_user="''${BROWSER_HARNESS_SSH_USER:-$(whoami)}"
        default_port="''${BROWSER_HARNESS_SSH_PORT:-''${JACK10_BROWSER_HARNESS_PORT:-''${JACK10_SSH_PORT:-22}}}"
        default_path="''${BROWSER_HARNESS_REPO_PATH:-''${JACK10_BROWSER_HARNESS_REPO_PATH:-git/browser-harness.git}}"
        user="''${BROWSER_HARNESS_SSH_USER:-}"
        host="''${BROWSER_HARNESS_SSH_HOST:-}"
        port="''${BROWSER_HARNESS_SSH_PORT:-}"
        path="''${BROWSER_HARNESS_REPO_PATH:-}"
        interactive=false
        [ -t 0 ] && interactive=true

        if [ -z "$host" ] && ! $interactive; then
          return 1
        fi

        if [ -z "$user" ]; then
          if $interactive; then
            read -rp "browser-harness SSH user [$default_user]: " user
            user="''${user:-$default_user}"
          else
            user="$default_user"
          fi
        fi

        if [ -z "$host" ]; then
          read -rp "browser-harness SSH host: " host
        fi
        if [ -z "$host" ]; then
          echo "browser-harness SSH host is required." >&2
          return 1
        fi

        if [ -z "$port" ]; then
          if $interactive; then
            read -rp "browser-harness SSH port [$default_port]: " port
            port="''${port:-$default_port}"
          else
            port="$default_port"
          fi
        fi

        if [ -z "$path" ]; then
          if $interactive; then
            read -rp "browser-harness repo path on host [$default_path]: " path
            path="''${path:-$default_path}"
          else
            path="$default_path"
          fi
        fi

        browser_harness_git_ssh_url "$user@$host" "$port" "$path"
      }

      target="$HOME/projects/browser-harness"
      if [ ! -d "$target/.git" ]; then
        if browser_harness_resolve_git_url; then
          $DRY_RUN_CMD mkdir -p "$HOME/projects"
          if $DRY_RUN_CMD env GIT_SSH_COMMAND="$browser_harness_ssh_command" ${pkgs.git}/bin/git clone --quiet "$browser_harness_git_url" "$target"; then
            echo "browser-harness: cloned to $target"
          else
            echo "browser-harness: clone failed; check SSH host/port/path or set BROWSER_HARNESS_GIT_URL" >&2
          fi
        else
          echo "browser-harness: not cloned; set BROWSER_HARNESS_GIT_URL or BROWSER_HARNESS_SSH_HOST" >&2
        fi
      fi
    '';
}
