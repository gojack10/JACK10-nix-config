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
      # Toggle mirror mode:
      #   ON:  save workspace layout, consolidate to laptop, mirror laptop to externals
      #   OFF: kill mirrors, restore workspaces to original outputs

      STATE_FILE="/tmp/sway-mirror-state"
      LAPTOP="eDP-1"
      JQ="${pkgs.jq}/bin/jq"

      if pgrep -x wl-mirror >/dev/null 2>&1; then
        # === MIRROR OFF ===
        pkill -x wl-mirror

        if [ -f "$STATE_FILE" ]; then
          # Get saved workspace names before restoring
          saved_names=$($JQ -r '.workspaces[].name' "$STATE_FILE")

          focused_ws=$($JQ -r '.focused' "$STATE_FILE")
          $JQ -r '.workspaces[] | "\(.name) \(.output)"' "$STATE_FILE" | while read -r ws output; do
            swaymsg "workspace $ws; move workspace to output $output" 2>/dev/null
          done
          [ -n "$focused_ws" ] && swaymsg "workspace $focused_ws"

          # Remove any workspaces that didn't exist before mirroring (e.g. auto-created 10)
          for ws in $(swaymsg -t get_workspaces | $JQ -r '.[].name'); do
            if ! echo "$saved_names" | grep -qx "$ws"; then
              swaymsg "workspace $ws; move workspace to output $LAPTOP" 2>/dev/null
            fi
          done

          rm -f "$STATE_FILE"
        fi
      else
        # === MIRROR ON ===
        # Save state as JSON
        focused=$(swaymsg -t get_workspaces | $JQ -r '.[] | select(.focused) | .name')
        swaymsg -t get_workspaces | $JQ --arg f "$focused" \
          '{focused: $f, workspaces: [.[] | {name, output}]}' > "$STATE_FILE"

        # Move all workspaces to laptop
        swaymsg -t get_workspaces | $JQ -r '.[].name' | while read -r ws; do
          swaymsg "workspace $ws; move workspace to output $LAPTOP"
        done
        swaymsg "workspace $focused"

        # Mirror laptop fullscreen onto each external output
        swaymsg -t get_outputs | $JQ -r '.[].name' | while read -r output; do
          [ "$output" = "$LAPTOP" ] && continue
          /usr/bin/wl-mirror --fullscreen-output "$output" "$LAPTOP" &
        done
      fi
    '';
  };

  # Start the mouse daemon with sway and center cursor on boot
  wayland.windowManager.sway.config.startup = [
    { command = "~/.local/bin/sway-mouse-daemon"; }
    { command = "~/.local/bin/sway-center-cursor output"; }
  ];
}
