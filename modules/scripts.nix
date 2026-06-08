{ config, pkgs, ... }:

{
  home.file.".local/share/JACK10-nix-config/ssh-env.sh" = {
    source = ../scripts/lib/ssh-env.sh;
    force = true;
  };

  home.file.".local/bin/tmux-status" = {
    source = ../scripts/tmux-status;
    executable = true;
    force = true;
  };

  home.file.".local/bin/deepwork-status" = {
    source = ../scripts/deepwork-status;
    executable = true;
    force = true;
  };

  home.file.".local/bin/tokens" = {
    source = ../scripts/tokens;
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

  home.file.".local/bin/pi-push" = {
    source = ../scripts/pi-push;
    executable = true;
    force = true;
  };

  home.file.".local/bin/hms" = {
    source = ../scripts/hms;
    executable = true;
    force = true;
  };

  home.file.".local/bin/music" = {
    source = ../scripts/music;
    executable = true;
    force = true;
  };

  home.file.".local/bin/rip" = {
    source = ../scripts/rip;
    executable = true;
    force = true;
  };
}
