{ config, pkgs, ... }:

{
  home.file = {
    ".config/waybar/config".text = builtins.toJSON {
      layer = "top";
      position = "top";
      height = 18;
      modules-left = [ "sway/workspaces" "sway/mode" ];
      modules-right = [ "cpu" "memory" "network" "battery" "clock" ];

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

      network = {
        interface = "wl*";
        format-wifi = "{essid}";
        format-disconnected = "disconnected";
        interval = 3;
      };

      battery = {
        format = "BAT {capacity}%";
        format-charging = "CHG {capacity}%";
        format-full = "FULL";
        interval = 5;
      };

      clock = {
        format = "{:%Y-%m-%d %H:%M}";
        interval = 1;
      };
    };

    ".config/waybar/style.css".text = ''
      * {
        font-family: "JetBrainsMono Nerd Font Mono", monospace;
        font-size: 9.5px;
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

      #cpu, #memory, #network, #battery, #pulseaudio, #clock {
        padding: 0 10px;
        color: #d0d0d0;
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
