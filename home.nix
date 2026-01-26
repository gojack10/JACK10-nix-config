{ config, pkgs, fontSize, hostname, useSystemSway, ... }:

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
  fonts.fontconfig.defaultFonts = {
    monospace = [ "JetBrainsMono Nerd Font Mono" "Symbols Nerd Font Mono" ];
    emoji = [ "Noto Color Emoji" ];
  };

  # Dark mode for GTK apps
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    font = {
      name = "JetBrainsMono Nerd Font";
      size = builtins.floor (fontSize + 0.5);
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
    # PipeWire needs these to find Nix-installed plugins
    SPA_PLUGIN_DIR = "${config.home.homeDirectory}/.nix-profile/lib/spa-0.2";
    PIPEWIRE_MODULE_DIR = "${config.home.homeDirectory}/.nix-profile/lib/pipewire-0.3";
  };
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.nix-profile/bin"
  ];

  # Nix settings (enable flakes)
  nix = {
    package = pkgs.nix;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  # Local scripts
  home.file.".local/bin/askpass-wofi" = {
    executable = true;
    text = ''
      #!/bin/sh
      bemenu -x -p "sudo:" --fn "JetBrainsMono Nerd Font ${toString (builtins.floor (fontSize + 2.5))}"
    '';
  };

  home.file.".local/bin/sway-workspace-outputs" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Move workspaces 4+ to external monitor if connected

      assign_workspaces() {
        external=$(swaymsg -t get_outputs -r | grep -o '"name": "[^"]*"' | cut -d'"' -f4 | grep -v eDP-1 | head -1)

        if [ -n "$external" ]; then
          for ws in 4 5 6 7 8 9 10; do
            swaymsg "workspace $ws output $external"
          done
          # Switch external to workspace 4
          swaymsg "focus output $external"
          swaymsg "workspace 4"
        fi
      }

      # Run once immediately
      assign_workspaces

      # Then subscribe to output events
      swaymsg -t subscribe '["output"]' --monitor | while read -r event; do
        sleep 0.5  # let output settle
        assign_workspaces
      done
    '';
  };
}
