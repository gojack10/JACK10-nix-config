{ config, lib, pkgs, ... }: {
  # Scripts sourced from ../scripts/ are managed by Home Manager and linked to ~/.local/bin.
  # Add new script entries below following the same pattern.

  home.file.".local/bin/worker" = {
    source = ../scripts/worker;
    executable = true;
    force = true;
  };

  home.file.".local/bin/cos" = {
    source = ../scripts/cos;
    executable = true;
    force = true;
  };

  home.file.".local/bin/cofounder" = {
    source = ../scripts/cofounder;
    executable = true;
    force = true;
  };

  home.file.".local/bin/jack" = {
    source = ../scripts/jack;
    executable = true;
    force = true;
  };

  home.file.".local/bin/rip" = {
    source = ../scripts/rip;
    executable = true;
    force = true;
  };

  home.file.".local/bin/transcribe" = {
    source = ../scripts/transcribe;
    executable = true;
    force = true;
  };

  home.file.".local/bin/hms" = {
    source = ../scripts/hms;
    executable = true;
    force = true;
  };

  home.file.".local/bin/pi-setup" = {
    source = ../scripts/pi-setup;
    executable = true;
    force = true;
  };

  home.file.".local/bin/pi-update" = {
    source = ../scripts/pi-update;
    executable = true;
    force = true;
  };

  home.file.".local/bin/pi-patches" = {
    source = ../scripts/pi-patches;
    executable = true;
    force = true;
  };

  home.file.".local/bin/pi-push" = {
    source = ../scripts/pi-push;
    executable = true;
    force = true;
  };

  home.file.".local/bin/tmux-status" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ../scripts/tmux-status;
    executable = true;
    force = true;
  };

  home.file.".local/bin/deepwork-status" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ../scripts/deepwork-status;
    executable = true;
    force = true;
  };

  home.file.".local/bin/tmux-restart" = {
    executable = true;
    force = true;
    text = ''
      #!/bin/sh
      set -eu

      bin='${config.programs.tmux.package}/bin/tmux'
      save='${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/save.sh'
      restore='${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/restore.sh'
      helper="__tmux_restore_$$"
      log="$HOME/.cache/tmux-restart.log"

      mkdir -p "$HOME/.cache"
      "$bin" set-option -g @resurrect-processes ':all:'
      "$save" quiet
      nohup sh -c '
        set -eu
        sleep 1
        TMUX= "$1" kill-server
        TMUX= "$1" new-session -d -s "$3" \
          "\"$1\" set-option -g @resurrect-processes :all:; exec \"$2\""
      ' sh "$bin" "$restore" "$helper" >"$log" 2>&1 &

      printf 'tmux saved; server will restart and restore. Reattach with: tmux attach\n'
    '';
  };
}
