{ lib, pkgs, ... }: {
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
}
