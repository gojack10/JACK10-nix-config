{ config, pkgs, lib, fontSize, useSystemSway, ... }:

{
  wayland.windowManager.sway = {
    enable = true;
    package = if useSystemSway then null else pkgs.sway;
    wrapperFeatures.gtk = true;
    config = {
      modifier = "Mod4";
      terminal = "foot";

      fonts = {
        names = [ "JetBrainsMono Nerd Font" ];
        size = fontSize;
      };

      gaps = {
        inner = 10;
        outer = 6;
        smartBorders = "on";
        smartGaps = true;
      };

      window = {
        border = 2;
        titlebar = false;
      };

      floating = {
        border = 2;
        titlebar = false;
      };

      colors = {
        focused = {
          border = "#6f6f6f";
          background = "#6f6f6f";
          text = "#ffffff";
          indicator = "#6f6f6f";
          childBorder = "#6f6f6f";
        };
        focusedInactive = {
          border = "#3a3a3a";
          background = "#3a3a3a";
          text = "#8a8a8a";
          indicator = "#3a3a3a";
          childBorder = "#3a3a3a";
        };
        unfocused = {
          border = "#3a3a3a";
          background = "#3a3a3a";
          text = "#8a8a8a";
          indicator = "#3a3a3a";
          childBorder = "#3a3a3a";
        };
        urgent = {
          border = "#ff5555";
          background = "#ff5555";
          text = "#ffffff";
          indicator = "#ff5555";
          childBorder = "#ff5555";
        };
      };

      keybindings = let modifier = "Mod4"; in {
        "${modifier}+Return" = "exec foot";
        "${modifier}+d" = "exec wofi --show drun";
        "${modifier}+Shift+q" = "kill";
        "${modifier}+f" = "fullscreen toggle";
        "${modifier}+e" = "layout toggle split";
        "${modifier}+s" = "layout stacking";
        "${modifier}+w" = "layout tabbed";
        "${modifier}+Shift+space" = "floating toggle";
        "${modifier}+Shift+r" = "reload";
        "${modifier}+space" = "scratchpad show";

        # Focus (hjkl) - center cursor on window
        "${modifier}+h" = "focus left; exec ~/.local/bin/sway-center-cursor window";
        "${modifier}+j" = "focus down; exec ~/.local/bin/sway-center-cursor window";
        "${modifier}+k" = "focus up; exec ~/.local/bin/sway-center-cursor window";
        "${modifier}+l" = "focus right; exec ~/.local/bin/sway-center-cursor window";

        # Move window (Shift+hjkl) - center cursor on window after move
        "${modifier}+Shift+h" = "move left; exec ~/.local/bin/sway-center-cursor window";
        "${modifier}+Shift+j" = "move down; exec ~/.local/bin/sway-center-cursor window";
        "${modifier}+Shift+k" = "move up; exec ~/.local/bin/sway-center-cursor window";
        "${modifier}+Shift+l" = "move right; exec ~/.local/bin/sway-center-cursor window";

        # Move window to other output (Ctrl+hjkl) - follow and center cursor
        "${modifier}+Ctrl+h" = "move container to output left; focus output left; exec ~/.local/bin/sway-center-cursor window";
        "${modifier}+Ctrl+l" = "move container to output right; focus output right; exec ~/.local/bin/sway-center-cursor window";

        # Focus other output directly (Alt+hjkl)
        "${modifier}+Alt+h" = "focus output left; exec ~/.local/bin/sway-center-cursor output";
        "${modifier}+Alt+l" = "focus output right; exec ~/.local/bin/sway-center-cursor output";

        # Workspaces - center cursor on output
        "${modifier}+1" = "workspace 1; exec ~/.local/bin/sway-center-cursor output";
        "${modifier}+2" = "workspace 2; exec ~/.local/bin/sway-center-cursor output";
        "${modifier}+3" = "workspace 3; exec ~/.local/bin/sway-center-cursor output";
        "${modifier}+4" = "workspace 4; exec ~/.local/bin/sway-center-cursor output";
        "${modifier}+5" = "workspace 5; exec ~/.local/bin/sway-center-cursor output";
        "${modifier}+6" = "workspace 6; exec ~/.local/bin/sway-center-cursor output";
        "${modifier}+7" = "workspace 7; exec ~/.local/bin/sway-center-cursor output";
        "${modifier}+8" = "workspace 8; exec ~/.local/bin/sway-center-cursor output";
        "${modifier}+9" = "workspace 9; exec ~/.local/bin/sway-center-cursor output";
        "${modifier}+0" = "workspace 10; exec ~/.local/bin/sway-center-cursor output";

        "${modifier}+Shift+1" = "move container to workspace 1";
        "${modifier}+Shift+2" = "move container to workspace 2";
        "${modifier}+Shift+3" = "move container to workspace 3";
        "${modifier}+Shift+4" = "move container to workspace 4";
        "${modifier}+Shift+5" = "move container to workspace 5";
        "${modifier}+Shift+6" = "move container to workspace 6";
        "${modifier}+Shift+7" = "move container to workspace 7";
        "${modifier}+Shift+8" = "move container to workspace 8";
        "${modifier}+Shift+9" = "move container to workspace 9";
        "${modifier}+Shift+0" = "move container to workspace 10";

        # Volume/brightness
        "XF86MonBrightnessUp" = "exec brightnessctl set +5%";
        "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
        "XF86AudioRaiseVolume" = "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
        "XF86AudioLowerVolume" = "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        "XF86AudioMute" = "exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";

        # Gammastep toggle (Fn+F9)
        "XF86Tools" = "exec pkill -USR1 gammastep";

        # Screenshot (idempotent - won't spawn duplicates)
        "Print" = "exec pgrep -x slurp || grim -g \"$(slurp)\" - | swappy -f -";

        # Deep work timer toggle
        "${modifier}+Shift+d" = "exec ~/.local/bin/deepwork toggle";

        # Resize mode
        "${modifier}+r" = "mode resize";
      };

      modes = {
        resize = {
          # hjkl to grow, Shift+hjkl to shrink
          "h" = "resize grow left 20px";
          "j" = "resize grow down 20px";
          "k" = "resize grow up 20px";
          "l" = "resize grow right 20px";
          "Shift+h" = "resize shrink left 20px";
          "Shift+j" = "resize shrink down 20px";
          "Shift+k" = "resize shrink up 20px";
          "Shift+l" = "resize shrink right 20px";
          "Escape" = "mode default";
        };
      };

      bars = [];

      startup = [
        { command = "waybar"; }
        { command = "mako"; }
        { command = "nm-applet --indicator"; }
        { command = "gammastep"; }
        { command = "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway"; }
        { command = "pipewire"; }
        { command = "pipewire-pulse"; }
        { command = "wireplumber"; }
        # portals auto-start via D-Bus activation (installed via xbps, not nix)
        { command = "wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 30%"; }
        { command = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0%"; }
      ];

      input = {
        "type:touchpad" = {
          tap = "enabled";
          natural_scroll = "disabled";
          accel_profile = "adaptive";
          pointer_accel = "0.5";
        };
        "type:keyboard" = {
          repeat_delay = "300";
          repeat_rate = "30";
        };
      };

      output = {
        "*" = {
          bg = "${config.home.homeDirectory}/.config/home-manager/bg.png fill";
          scale = "1.0";
        };
        "eDP-1" = {
          position = "0 0";
        };
        "Sceptre Tech Inc Sceptre C32 0x00000001" = {
          mode = "1920x1080@120Hz";
          position = "1920 0";
        };
      };

      window.commands = [
        # Float portal file dialogs and keep on focused workspace
        { command = "floating enable"; criteria = { app_id = "xdg-desktop-portal-gtk"; }; }
        { command = "move position center"; criteria = { app_id = "xdg-desktop-portal-gtk"; }; }
      ];
    };

    extraConfig = ''
      # Default workspaces on login (not locked - just initial state)
      workspace 1 output eDP-1
      workspace 2 output HDMI-A-2
      workspace 2
      workspace 1
      seat seat0 xcursor_theme retrosmart-xcursor-black 24
    '';
  };
}
