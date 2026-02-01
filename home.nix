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

  # mpv - use system mpv (Nix mpv can't access Void's mesa/VAAPI drivers)
  # Install via: sudo xbps-install mpv

  home.file.".config/mpv/mpv.conf".text = ''
    # Force Wayland
    gpu-context=wayland
    vo=gpu-next
    # Hardware decoding
    hwdec=auto-safe
    # Window behavior
    fs=no
    keep-open=yes
    save-position-on-quit=yes
    # OSD styling
    osd-font=JetBrainsMono Nerd Font
    osd-font-size=24
  '';

  home.file.".config/mpv/input.conf".text = ''
    # Vim-like bindings
    l seek 5
    h seek -5
    j seek -60
    k seek 60
    H add chapter -1
    L add chapter 1
  '';

  # Default applications (xdg-open)
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Web
      "text/html" = "brave-browser.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "x-scheme-handler/about" = "brave-browser.desktop";
      "x-scheme-handler/unknown" = "brave-browser.desktop";
      # Documents
      "application/pdf" = "brave-browser.desktop";
      # Video - mpv
      "video/webm" = "mpv.desktop";
      "video/mp4" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/avi" = "mpv.desktop";
      "video/x-msvideo" = "mpv.desktop";
      "video/quicktime" = "mpv.desktop";
      "video/x-flv" = "mpv.desktop";
      "video/ogg" = "mpv.desktop";
      # Audio - mpv
      "audio/mpeg" = "mpv.desktop";
      "audio/mp3" = "mpv.desktop";
      "audio/flac" = "mpv.desktop";
      "audio/ogg" = "mpv.desktop";
      "audio/wav" = "mpv.desktop";
      "audio/x-wav" = "mpv.desktop";
      "audio/aac" = "mpv.desktop";
      "audio/mp4" = "mpv.desktop";
      "audio/x-m4a" = "mpv.desktop";
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
