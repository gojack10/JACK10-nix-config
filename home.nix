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
    ./modules/wayland/mouse.nix
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
    cursorTheme = {
      name = "retrosmart-xcursor-black";
      size = 24;
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

  # dconf settings (GTK portal reads theme from here)
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = "Adwaita-dark";
      };
    };
  };

  home.sessionVariables = {
    LANG = "C.UTF-8";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_CURRENT_DESKTOP = "sway";
    XDG_SESSION_TYPE = "wayland";
    GTK_USE_PORTAL = "1";  # Chromium/Brave use portal for file dialogs
    # gsettings schema path for GTK portal dark theme
    GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/gsettings-desktop-schemas-${pkgs.gsettings-desktop-schemas.version}/glib-2.0/schemas";
    # Cursor theme for Wayland
    XCURSOR_THEME = "retrosmart-xcursor-black";
    XCURSOR_SIZE = "24";
    # Disable OpenCode's default system prompt
    OPENCODE_DISABLE_SYSTEM_PROMPT = "true";
  };
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.nix-profile/bin"
    "$HOME/.cargo/bin"
  ];

  # Nix settings (enable flakes)
  nix = {
    package = pkgs.nix;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  # Default applications (xdg-open)
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "brave-browser.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "x-scheme-handler/about" = "brave-browser.desktop";
      "x-scheme-handler/unknown" = "brave-browser.desktop";
      "video/webm" = "brave-browser.desktop";
      "video/mp4" = "brave-browser.desktop";
      "video/x-matroska" = "brave-browser.desktop";
      "audio/mpeg" = "brave-browser.desktop";
      "application/pdf" = "brave-browser.desktop";
    };
  };

  # Gammastep (software dimming beyond hardware minimum)
  services.gammastep = {
    enable = true;
    tray = true;
    dawnTime = "6:30-7:30";
    duskTime = "19:00-20:00";
    temperature = {
      day = 6500;    # neutral daylight
      night = 2500;  # warm + perceived dimmer
    };
    settings.general.brightness-night = 0.7;  # additional software dimming
  };

  # Cursor theme (Retrosmart black)
  home.file.".local/share/icons/retrosmart-xcursor-black".source = ./assets/cursors/retrosmart-xcursor-black;

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
