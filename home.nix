{ config, pkgs, ... }:

{
  imports = [
    ./modules/packages.nix
    # Wayland
    ./modules/wayland/sway.nix
    ./modules/wayland/waybar.nix
    ./modules/wayland/foot.nix
    ./modules/wayland/wofi.nix
    ./modules/wayland/mako.nix
    # Shell
    ./modules/shell/zsh.nix
    ./modules/shell/tmux.nix
    ./modules/shell/git.nix
    # Editor
    ./modules/editor/nvim.nix
  ];

  home.username = "jack";
  home.homeDirectory = "/home/jack";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    LANG = "C.UTF-8";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_CURRENT_DESKTOP = "sway";
    XDG_SESSION_TYPE = "wayland";
  };
}
