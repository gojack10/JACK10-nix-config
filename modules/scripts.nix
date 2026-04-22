{ config, pkgs, ... }:

{
  home.file.".local/bin/tokens" = {
    source = ../scripts/tokens;
    executable = true;
  };

  home.file.".local/bin/pi-setup" = {
    source = ../scripts/pi-setup;
    executable = true;
  };
}
