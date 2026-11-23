{ config, lib, pkgs, configRevision, ... }:

let
  tmux = config.programs.tmux.package;
  # The tmux build: a GitHub source names its owner/repo@commit (Jack's fork).
  tmuxSource = lib.optionalString (tmux.src ? owner && tmux.src ? rev)
    " ${tmux.src.owner}/${tmux.src.repo}@${lib.substring 0 7 tmux.src.rev}";
  tmuxOil = pkgs.writeShellApplication {
    name = "tmux-oil";
    runtimeInputs = [ tmux pkgs.neovim ];
    # Consume the same shared editor preferences as the regular Nix editor,
    # then apply only the tree-menu-specific profile to the session buffer.
    text = ''
      export TMUX_OIL_SHARED_CONFIG=${./editor/files/shared.lua}
      export TMUX_OIL_TREE_MENU_CONFIG=${./editor/files/tree-menu-specific.lua}
      export TMUX_OIL_BUILD='JACK10-nix-config ${configRevision} - tmux ${tmux.version}${tmuxSource}'
    '' + builtins.readFile ../scripts/tmux-oil;
  };
in {
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

  home.file.".local/bin/music" = {
    source = ../scripts/music;
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

  home.file.".local/bin/tmux-oil" = {
    source = "${tmuxOil}/bin/tmux-oil";
    executable = true;
    force = true;
  };

  home.file.".local/bin/stimulant" = lib.mkIf pkgs.stdenv.isDarwin {
    source = ../scripts/stimulant;
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
