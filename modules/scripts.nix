{ config, pkgs, ... }:

{
  home.file.".local/bin/tokens" = {
    source = ../scripts/tokens;
    executable = true;
  };
}
