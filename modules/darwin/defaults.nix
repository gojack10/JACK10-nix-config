{ config, pkgs, lib, ... }:

{
  home.activation.darwinKeyRepeat = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Current preferred values discovered with:
    #   defaults read -g KeyRepeat
    #   defaults read -g InitialKeyRepeat
    /usr/bin/defaults write -g KeyRepeat -int 2
    /usr/bin/defaults write -g InitialKeyRepeat -int 10
  '';
}
