{ config, pkgs, lib, ... }:

let
  hostnameFile = builtins.readFile /etc/hostname;
  hostname = builtins.replaceStrings ["\n"] [""] hostnameFile;
  useSystemSway = builtins.elem hostname [ "litetop" ];
in
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
        size = 10.0;
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

        # Focus (hjkl)
        "${modifier}+h" = "focus left";
        "${modifier}+j" = "focus down";
        "${modifier}+k" = "focus up";
        "${modifier}+l" = "focus right";

        # Move (Shift+hjkl)
        "${modifier}+Shift+h" = "move left";
        "${modifier}+Shift+j" = "move down";
        "${modifier}+Shift+k" = "move up";
        "${modifier}+Shift+l" = "move right";

        # Workspaces
        "${modifier}+1" = "workspace 1";
        "${modifier}+2" = "workspace 2";
        "${modifier}+3" = "workspace 3";
        "${modifier}+4" = "workspace 4";
        "${modifier}+5" = "workspace 5";
        "${modifier}+6" = "workspace 6";
        "${modifier}+7" = "workspace 7";
        "${modifier}+8" = "workspace 8";
        "${modifier}+9" = "workspace 9";
        "${modifier}+0" = "workspace 10";

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
        "XF86AudioRaiseVolume" = "exec pactl set-sink-volume @DEFAULT_SINK@ +5%";
        "XF86AudioLowerVolume" = "exec pactl set-sink-volume @DEFAULT_SINK@ -5%";
        "XF86AudioMute" = "exec pactl set-sink-mute @DEFAULT_SINK@ toggle";

        # Screenshot
        "Print" = "exec grim -g \"$(slurp)\" - | wl-copy";
      };

      bars = [];

      startup = [
        { command = "waybar"; }
        { command = "mako"; }
        { command = "nm-applet --indicator"; }
      ];

      input = {
        "type:touchpad" = {
          tap = "enabled";
          natural_scroll = "enabled";
          accel_profile = "adaptive";
          pointer_accel = "0.3";
        };
        "type:keyboard" = {
          repeat_delay = "300";
          repeat_rate = "30";
        };
      };

      output = {
        "*" = {
          bg = "#0f0f0f solid_color";
        };
      };
    };
  };
}
