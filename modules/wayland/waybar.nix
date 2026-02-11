{ config, pkgs, fontSizeWaybar, ... }:

{
  home.file = {
    ".config/waybar/config".text = builtins.toJSON {
      layer = "top";
      position = "top";
      height = 18;
      modules-left = [ "sway/workspaces" "sway/mode" ];
      modules-center = [ "custom/deepwork" ];
      modules-right = [ "cpu" "memory" "custom/network" "battery" "custom/mic" "pulseaudio" "custom/clock" ];

      "sway/workspaces" = {
        disable-scroll = true;
        format = "{index}";
      };

      cpu = {
        format = "CPU {usage:2}%";
        interval = 1;
      };

      memory = {
        format = "MEM {used:0.1f}G";
        interval = 2;
      };

      "custom/network" = {
        exec = "if ip link show enp4s0 2>/dev/null | grep -q 'state UP'; then echo 'ETHERNET'; elif iwctl station wlp0s20f3 show 2>/dev/null | grep -q 'Connected'; then iwctl station wlp0s20f3 show | grep 'Connected network' | sed 's/.*Connected network[[:space:]]*//; s/[[:space:]]*$//' ; else echo 'disconnected'; fi";
        interval = 3;
      };

      battery = {
        format = "BAT {capacity}%";
        format-charging = "CHG {capacity}%";
        format-full = "FULL";
        interval = 5;
      };

      "custom/clock" = {
        exec = "date '+%a %Y-%m-%d %H:%M:%S' | sed 's/^[^ ]*/\\U&/'";
        interval = 1;
      };

      pulseaudio = {
        format = "VOL {volume}%";
        format-muted = "VOL MUTE";
        on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        scroll-step = 5;
      };

      "custom/mic" = {
        exec = "bash -c 'vol=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | awk \"{print int(\\$2*100)}\"); mute=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep MUTED); if [ -n \"$mute\" ]; then echo \"MIC MUTE\"; else echo \"MIC $vol%\"; fi'";
        interval = 1;
        on-click = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
      };

      "custom/deepwork" = {
        exec = "~/.local/bin/deepwork status 2>/dev/null || echo '󰔟 Ready'";
        interval = 1;
        on-click = "foot ~/.local/bin/deepwork stats";
      };
    };

    ".config/waybar/style.css".text = ''
      * {
        font-family: "JetBrainsMono Nerd Font Mono", monospace;
        font-size: ${toString fontSizeWaybar}px;
        border: none;
        border-radius: 0;
        min-height: 0;
      }

      window#waybar {
        background: #0f0f0f;
        color: #d0d0d0;
      }

      #workspaces button {
        padding: 0 8px;
        color: #8a8a8a;
        background: transparent;
      }

      #workspaces button.focused {
        background: #6f6f6f;
        color: #ffffff;
      }

      #workspaces button.urgent {
        background: #ff5555;
        color: #ffffff;
      }

      #cpu, #memory, #custom-network, #battery, #pulseaudio, #custom-clock, #custom-mic, #custom-deepwork {
        padding: 0 10px;
        color: #d0d0d0;
      }

      #pulseaudio.muted, #custom-mic.muted {
        color: #ff5555;
      }

      #battery.charging {
        color: #88cc88;
      }

      #battery.warning {
        color: #ffcc00;
      }

      #battery.critical {
        color: #ff5555;
      }
    '';
  };
}
