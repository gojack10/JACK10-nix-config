{ config, pkgs, ... }:

{
  home.file.".config/mako/config".text = ''
    font=JetBrainsMono Nerd Font 10
    background-color=#0f0f0f
    text-color=#d0d0d0
    border-color=#6f6f6f
    border-size=2
    padding=10
    default-timeout=5000
  '';
}
