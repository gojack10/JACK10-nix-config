{ config, pkgs, ... }:

{
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

  home.file.".local/bin/hms" = {
    source = ../scripts/hms;
    executable = true;
    force = true;
  };
}
