{ config, pkgs, lib, ... }:

let
  home = config.home.homeDirectory;
  localConfigDir = "${home}/.config/JACK10-nix-config/local";
  localConfig = "${localConfigDir}/ssh.env";
in {
  home.packages = with pkgs; [
    openssh
    autossh
  ];

  home.activation.prepare-jack10-ssh-env = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${lib.escapeShellArg localConfigDir}
    if [ -f ${lib.escapeShellArg localConfig} ]; then
      chmod 600 ${lib.escapeShellArg localConfig} || true
    fi
  '';
}
