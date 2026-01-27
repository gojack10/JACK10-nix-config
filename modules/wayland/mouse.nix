{ config, pkgs, lib, ... }:

{
  # Disable automatic mouse warping - we handle it manually per-action
  # Also move cursor off-screen during init (before anything renders)
  wayland.windowManager.sway.extraConfig = lib.mkAfter ''
    mouse_warping none
    seat seat0 cursor set -100 -100
  '';

  home.file.".local/bin/sway-center-cursor" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Center cursor on window or output
      # Usage: sway-center-cursor [window|output]

      case "$1" in
        window)
          # Get focused window geometry and center cursor on it
          coords=$(swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '
            recurse(.nodes[], .floating_nodes[]) |
            select(.focused == true) |
            "\(.rect.x + .rect.width/2 | floor) \(.rect.y + .rect.height/2 | floor)"
          ' | head -1)
          ;;
        output|*)
          # Get focused output geometry and center cursor on it
          coords=$(swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '
            .[] | select(.focused == true) |
            "\(.rect.x + .rect.width/2 | floor) \(.rect.y + .rect.height/2 | floor)"
          ')
          ;;
      esac

      if [ -n "$coords" ]; then
        set -- $coords
        swaymsg seat seat0 cursor set "$1" "$2"
      fi
    '';
  };

  home.file.".local/bin/sway-mouse-daemon" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Daemon that listens for window events and centers cursor on new windows

      swaymsg -t subscribe '["window"]' --monitor | while read -r event; do
        change=$(echo "$event" | ${pkgs.jq}/bin/jq -r '.change')
        if [ "$change" = "new" ]; then
          sleep 0.05  # let window settle
          ~/.local/bin/sway-center-cursor window
        fi
      done
    '';
  };

  # Start the mouse daemon with sway and center cursor on boot
  wayland.windowManager.sway.config.startup = [
    { command = "~/.local/bin/sway-mouse-daemon"; }
    { command = "~/.local/bin/sway-center-cursor output"; }
  ];
}
