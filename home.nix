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
    ./modules/shell/lf.nix
    # Editor
    ./modules/editor/nvim.nix
  ];

  home.username = "jack";
  home.homeDirectory = "/home/jack";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  fonts.fontconfig.enable = true;

  # Dark mode for GTK apps
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 10;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-xft-dpi = 98304;  # 96 * 1024 * ~1.0 - slightly smaller
    };
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };

  # Qt dark mode (follows GTK)
  qt = {
    enable = true;
    platformTheme.name = "gtk";
  };

  # Disable dconf (no dbus session on Void)
  dconf.enable = false;

  home.sessionVariables = {
    LANG = "C.UTF-8";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_CURRENT_DESKTOP = "sway";
    XDG_SESSION_TYPE = "wayland";
  };
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.nix-profile/bin"
  ];

  # Local scripts
  home.file.".local/bin/askpass-wofi" = {
    executable = true;
    text = ''
      #!/bin/sh
      bemenu -x -p "sudo:" --fn "JetBrainsMono Nerd Font 12"
    '';
  };
}
