{ config, pkgs, lib, ... }:

{
  # Disable automatic mouse warping - we handle it manually per-action
  # Also move cursor off-screen during init (before anything renders)
  wayland.windowManager.sway.extraConfig = lib.mkAfter ''
    mouse_warping none
    seat seat0 cursor set -100 -100

    # External mouse config (pointer type, not touchpad)
    # TWEAK THIS: Run 'mouse-tuner' to find your ideal settings, then update here
    # Note: DPI is hardware-level (set via mouse buttons/software like piper for Logitech)
    # pointer_accel is a sensitivity multiplier (-1.0 to 1.0)
    input type:pointer {
      accel_profile flat
      pointer_accel 0.50
    }
  '';

  # Mouse tuner script - run 'mouse-tuner' to experiment with settings
  home.file.".local/bin/mouse-tuner" = {
    executable = true;
    source = ../../scripts/mouse-tuner.sh;
  };

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

  home.file.".local/bin/sway-swap-outputs" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Swap all workspaces between two outputs
      # Only operates when exactly 2 outputs are connected

      outputs=$(swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[].name')
      count=$(echo "$outputs" | wc -l)

      [ "$count" -ne 2 ] && exit 0

      output1=$(echo "$outputs" | sed -n '1p')
      output2=$(echo "$outputs" | sed -n '2p')

      # Remember which output has focus and which workspace is visible on each output
      focused=$(swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
      visible_on_1=$(swaymsg -t get_workspaces | ${pkgs.jq}/bin/jq -r ".[] | select(.output == \"$output1\" and .visible) | .name")
      visible_on_2=$(swaymsg -t get_workspaces | ${pkgs.jq}/bin/jq -r ".[] | select(.output == \"$output2\" and .visible) | .name")

      # Capture workspaces on each output before moving anything
      ws_on_1=$(swaymsg -t get_workspaces | ${pkgs.jq}/bin/jq -r ".[] | select(.output == \"$output1\") | .name")
      ws_on_2=$(swaymsg -t get_workspaces | ${pkgs.jq}/bin/jq -r ".[] | select(.output == \"$output2\") | .name")

      # Move output1 workspaces to output2
      for ws in $ws_on_1; do
        swaymsg "workspace $ws; move workspace to output $output2"
      done

      # Move output2 workspaces to output1
      for ws in $ws_on_2; do
        swaymsg "workspace $ws; move workspace to output $output1"
      done

      # Restore the previously visible workspace on each output
      # (the last-moved workspace may not be the one the user had visible)
      [ -n "$visible_on_1" ] && swaymsg "workspace $visible_on_1"
      [ -n "$visible_on_2" ] && swaymsg "workspace $visible_on_2"

      # Refocus the output the user was on
      swaymsg "focus output $focused"
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

  home.file.".local/bin/sway-mirror-toggle" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Toggle all outputs between mirror mode and extended mode
      # Mirror = all outputs at position 0,0 (sway composites them)
      # Extended = outputs placed side by side

      STATE_FILE="/tmp/sway-mirror-state"
      JQ="${pkgs.jq}/bin/jq"

      outputs=$(swaymsg -t get_outputs | $JQ -r '.[].name')
      count=$(echo "$outputs" | wc -l)

      # Need at least 2 outputs
      [ "$count" -lt 2 ] && exit 0

      primary=$(echo "$outputs" | head -1)

      if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "mirror" ]; then
        # Switch to EXTEND: place outputs side by side
        x=0
        for output in $outputs; do
          swaymsg output "$output" enable
          swaymsg output "$output" position "$x" 0
          w=$(swaymsg -t get_outputs | $JQ -r ".[] | select(.name == \"$output\") | .rect.width")
          x=$((x + w))
        done
        echo "extend" > "$STATE_FILE"
      else
        # Switch to MIRROR: move all workspaces to primary, disable others
        # Move every workspace to the primary output
        for ws in $(swaymsg -t get_workspaces | $JQ -r '.[].name'); do
          swaymsg "workspace $ws; move workspace to output $primary"
        done
        swaymsg "focus output $primary"
        # Disable all non-primary outputs (primary shows on all screens)
        for output in $outputs; do
          [ "$output" = "$primary" ] && continue
          swaymsg output "$output" disable
        done
        echo "mirror" > "$STATE_FILE"
      fi
    '';
  };

  # Start the mouse daemon with sway and center cursor on boot
  wayland.windowManager.sway.config.startup = [
    { command = "~/.local/bin/sway-mouse-daemon"; }
    { command = "~/.local/bin/sway-center-cursor output"; }
  ];
}
