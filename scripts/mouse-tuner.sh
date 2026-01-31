#!/bin/bash
# Mouse/Touchpad Tuner for Sway
# Live-adjust input settings and export to JSON
#
# USAGE:
#   mouse-tuner          # Interactive TUI mode
#   mouse-tuner --gui    # Zenity GUI mode (if installed)
#
# TWEAK THIS: When you find your perfect settings, update sway.nix input config

set -e

CONFIG_FILE="$HOME/.config/mouse-tuner.json"

# Get current settings from sway
get_current_settings() {
    swaymsg -t get_inputs -r | jq '[.[] | select(.type == "touchpad" or .type == "pointer")]'
}

# Apply a setting to a device
apply_setting() {
    local device="$1"
    local setting="$2"
    local value="$3"
    swaymsg "input '$device' $setting $value" 2>/dev/null || true
}

# Get device identifiers
get_touchpad() {
    swaymsg -t get_inputs -r | jq -r '.[] | select(.type == "touchpad") | .identifier' | head -1
}

get_pointer() {
    # Get non-touchpad pointer (external mouse)
    swaymsg -t get_inputs -r | jq -r '.[] | select(.type == "pointer") | .identifier' | head -1
}

# Export current settings to JSON
export_settings() {
    local touchpad=$(get_touchpad)
    local pointer=$(get_pointer)

    local touchpad_settings=$(swaymsg -t get_inputs -r | jq --arg id "$touchpad" '.[] | select(.identifier == $id) | .libinput')
    local pointer_settings=$(swaymsg -t get_inputs -r | jq --arg id "$pointer" '.[] | select(.identifier == $id) | .libinput')

    jq -n \
        --arg touchpad_id "$touchpad" \
        --argjson touchpad_settings "$touchpad_settings" \
        --arg pointer_id "$pointer" \
        --argjson pointer_settings "${pointer_settings:-null}" \
        '{
            touchpad: {
                identifier: $touchpad_id,
                settings: $touchpad_settings
            },
            pointer: {
                identifier: $pointer_id,
                settings: $pointer_settings
            },
            exported_at: now | strftime("%Y-%m-%d %H:%M:%S")
        }' > "$CONFIG_FILE"

    echo "Settings exported to: $CONFIG_FILE"
}

# TUI Mode
tui_mode() {
    local touchpad=$(get_touchpad)
    local pointer=$(get_pointer)
    local current_device="touchpad"
    local current_id="$touchpad"

    # Current values
    local accel_speed=0.0
    local accel_profile="adaptive"
    local natural_scroll="disabled"
    local tap="enabled"
    local scroll_factor=1.0

    # Load current values
    load_current() {
        local settings=$(swaymsg -t get_inputs -r | jq --arg id "$current_id" '.[] | select(.identifier == $id) | .libinput')
        accel_speed=$(echo "$settings" | jq -r '.accel_speed // 0')
        accel_profile=$(echo "$settings" | jq -r '.accel_profile // "adaptive"')
        natural_scroll=$(echo "$settings" | jq -r '.natural_scroll // "disabled"')
        tap=$(echo "$settings" | jq -r '.tap // "disabled"')
        scroll_factor=$(swaymsg -t get_inputs -r | jq -r --arg id "$current_id" '.[] | select(.identifier == $id) | .scroll_factor // 1')
    }

    load_current

    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              MOUSE/TOUCHPAD TUNER                            ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  Keys:                                                       ║"
    echo "║    Tab     - Switch device (touchpad/pointer)                ║"
    echo "║    j/k     - Decrease/Increase pointer_accel (±0.05)         ║"
    echo "║    J/K     - Decrease/Increase pointer_accel (±0.01)         ║"
    echo "║    s/S     - Decrease/Increase scroll_factor (±0.1)          ║"
    echo "║    a       - Toggle accel_profile (flat/adaptive)            ║"
    echo "║    n       - Toggle natural_scroll                           ║"
    echo "║    t       - Toggle tap (touchpad only)                      ║"
    echo "║    r       - Reset to defaults                               ║"
    echo "║    e       - Export settings to JSON                         ║"
    echo "║    q       - Quit                                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    while true; do
        # Display current settings
        echo -ne "\r\033[K"
        echo -ne "Device: \033[1;36m$current_device\033[0m ($current_id)"
        echo ""
        echo -ne "\033[K"
        printf "  pointer_accel:  \033[1;33m%+.2f\033[0m  [-1.0 to 1.0]\n" "$accel_speed"
        echo -ne "\033[K"
        echo "  accel_profile:  $accel_profile"
        echo -ne "\033[K"
        printf "  scroll_factor:  %.1f\n" "$scroll_factor"
        echo -ne "\033[K"
        echo "  natural_scroll: $natural_scroll"
        if [ "$current_device" = "touchpad" ]; then
            echo -ne "\033[K"
            echo "  tap:            $tap"
        fi
        echo ""
        echo -ne "Press key (q to quit): "

        # Move cursor up to overwrite
        if [ "$current_device" = "touchpad" ]; then
            echo -ne "\033[9A\r"
        else
            echo -ne "\033[8A\r"
        fi

        read -rsn1 key

        case "$key" in
            $'\t')  # Tab - switch device
                if [ "$current_device" = "touchpad" ] && [ -n "$pointer" ]; then
                    current_device="pointer"
                    current_id="$pointer"
                else
                    current_device="touchpad"
                    current_id="$touchpad"
                fi
                load_current
                ;;
            j)  # Decrease accel
                accel_speed=$(echo "$accel_speed - 0.05" | bc)
                [ "$(echo "$accel_speed < -1" | bc)" -eq 1 ] && accel_speed=-1.0
                apply_setting "$current_id" "pointer_accel" "$accel_speed"
                ;;
            k)  # Increase accel
                accel_speed=$(echo "$accel_speed + 0.05" | bc)
                [ "$(echo "$accel_speed > 1" | bc)" -eq 1 ] && accel_speed=1.0
                apply_setting "$current_id" "pointer_accel" "$accel_speed"
                ;;
            J)  # Fine decrease
                accel_speed=$(echo "$accel_speed - 0.01" | bc)
                [ "$(echo "$accel_speed < -1" | bc)" -eq 1 ] && accel_speed=-1.0
                apply_setting "$current_id" "pointer_accel" "$accel_speed"
                ;;
            K)  # Fine increase
                accel_speed=$(echo "$accel_speed + 0.01" | bc)
                [ "$(echo "$accel_speed > 1" | bc)" -eq 1 ] && accel_speed=1.0
                apply_setting "$current_id" "pointer_accel" "$accel_speed"
                ;;
            s)  # Decrease scroll factor
                scroll_factor=$(echo "$scroll_factor - 0.1" | bc)
                [ "$(echo "$scroll_factor < 0.1" | bc)" -eq 1 ] && scroll_factor=0.1
                apply_setting "$current_id" "scroll_factor" "$scroll_factor"
                ;;
            S)  # Increase scroll factor
                scroll_factor=$(echo "$scroll_factor + 0.1" | bc)
                apply_setting "$current_id" "scroll_factor" "$scroll_factor"
                ;;
            a)  # Toggle accel profile
                if [ "$accel_profile" = "adaptive" ]; then
                    accel_profile="flat"
                else
                    accel_profile="adaptive"
                fi
                apply_setting "$current_id" "accel_profile" "$accel_profile"
                ;;
            n)  # Toggle natural scroll
                if [ "$natural_scroll" = "disabled" ]; then
                    natural_scroll="enabled"
                else
                    natural_scroll="disabled"
                fi
                apply_setting "$current_id" "natural_scroll" "$natural_scroll"
                ;;
            t)  # Toggle tap
                if [ "$current_device" = "touchpad" ]; then
                    if [ "$tap" = "disabled" ]; then
                        tap="enabled"
                    else
                        tap="disabled"
                    fi
                    apply_setting "$current_id" "tap" "$tap"
                fi
                ;;
            r)  # Reset
                accel_speed=0.0
                accel_profile="adaptive"
                natural_scroll="disabled"
                tap="enabled"
                scroll_factor=1.0
                apply_setting "$current_id" "pointer_accel" "$accel_speed"
                apply_setting "$current_id" "accel_profile" "$accel_profile"
                apply_setting "$current_id" "natural_scroll" "$natural_scroll"
                apply_setting "$current_id" "scroll_factor" "$scroll_factor"
                [ "$current_device" = "touchpad" ] && apply_setting "$current_id" "tap" "$tap"
                ;;
            e)  # Export
                # Move cursor down and clear lines
                if [ "$current_device" = "touchpad" ]; then
                    echo -ne "\033[9B"
                else
                    echo -ne "\033[8B"
                fi
                export_settings
                echo ""
                echo "Copy these values to your sway.nix input config:"
                echo ""
                echo "  input = {"
                echo "    \"type:touchpad\" = {"
                printf "      pointer_accel = \"%+.2f\";\n" "$(swaymsg -t get_inputs -r | jq -r --arg id "$(get_touchpad)" '.[] | select(.identifier == $id) | .libinput.accel_speed')"
                echo "      accel_profile = \"$(swaymsg -t get_inputs -r | jq -r --arg id "$(get_touchpad)" '.[] | select(.identifier == $id) | .libinput.accel_profile')\";"
                echo "      # ... other settings"
                echo "    };"
                echo "  };"
                echo ""
                read -p "Press Enter to continue..." _
                clear
                ;;
            q)  # Quit
                if [ "$current_device" = "touchpad" ]; then
                    echo -ne "\033[9B"
                else
                    echo -ne "\033[8B"
                fi
                echo ""
                echo "Current settings:"
                echo "  pointer_accel: $accel_speed"
                echo "  accel_profile: $accel_profile"
                echo "  scroll_factor: $scroll_factor"
                echo ""
                echo "Run with 'e' to export, or add to sway.nix manually."
                exit 0
                ;;
        esac
    done
}

# GUI mode with zenity
gui_mode() {
    if ! command -v zenity &>/dev/null; then
        echo "zenity not installed. Run 'home-manager switch' to install it."
        echo "Falling back to TUI mode..."
        tui_mode
        return
    fi

    local touchpad=$(get_touchpad)
    local current_accel=$(swaymsg -t get_inputs -r | jq -r --arg id "$touchpad" '.[] | select(.identifier == $id) | .libinput.accel_speed')

    while true; do
        # Get new value from slider
        new_accel=$(zenity --scale \
            --title="Mouse/Touchpad Sensitivity" \
            --text="Pointer Acceleration\n(Move slider, OK to apply, Cancel when done)\n\nDevice: $touchpad" \
            --min-value=-100 \
            --max-value=100 \
            --value="$(echo "$current_accel * 100" | bc | cut -d. -f1)" \
            --step=1 \
            2>/dev/null) || break

        # Convert back to -1 to 1 range
        current_accel=$(echo "scale=2; $new_accel / 100" | bc)

        # Apply live
        apply_setting "$touchpad" "pointer_accel" "$current_accel"
    done

    # Offer to export
    if zenity --question --text="Export current settings to JSON?" 2>/dev/null; then
        export_settings
        zenity --info --text="Settings exported to:\n$CONFIG_FILE\n\npointer_accel: $current_accel" 2>/dev/null
    fi
}

# Main
case "${1:-}" in
    --gui|-g)
        gui_mode
        ;;
    --export|-e)
        export_settings
        ;;
    --help|-h)
        echo "Mouse/Touchpad Tuner for Sway"
        echo ""
        echo "Usage:"
        echo "  mouse-tuner          Interactive TUI mode"
        echo "  mouse-tuner --gui    Zenity GUI mode"
        echo "  mouse-tuner --export Export current settings to JSON"
        echo ""
        echo "Settings are applied live. Export when you find your perfect config."
        ;;
    *)
        tui_mode
        ;;
esac
