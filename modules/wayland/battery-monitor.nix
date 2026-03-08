{ config, pkgs, ... }:

{
  home.file.".local/bin/battery-monitor" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Battery monitor: notifications at 25%, 15%, 10% and auto-hibernate at 5%
      # Also logs capacity every 5 minutes to ~/.local/share/battery.log
      # Polls every 10s below 10%, every 30s otherwise

      INTERVAL=30
      NOTIFIED_25=0
      NOTIFIED_15=0
      NOTIFIED_10=0
      SUSPENDED=0
      LOG_FILE="$HOME/.local/share/battery.log"
      LOG_COUNTER=0

      mkdir -p "$(dirname "$LOG_FILE")"

      while true; do
        capacity=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
        status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)
        energy_now=$(cat /sys/class/power_supply/BAT0/energy_now 2>/dev/null)

        # Log every 10 iterations (5 minutes at 30s interval)
        LOG_COUNTER=$((LOG_COUNTER + 1))
        if [ "$LOG_COUNTER" -ge 10 ]; then
          echo "$(date '+%Y-%m-%d %H:%M:%S') ''${capacity}% ''${status} ''${energy_now}uWh" >> "$LOG_FILE"
          LOG_COUNTER=0
          # Keep log under 10000 lines
          if [ "$(wc -l < "$LOG_FILE")" -gt 10000 ]; then
            tail -5000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
          fi
        fi

        # Reset flags when charging
        if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
          NOTIFIED_25=0
          NOTIFIED_15=0
          NOTIFIED_10=0
          SUSPENDED=0
          sleep "$INTERVAL"
          continue
        fi

        if [ "$capacity" -le 5 ] && [ "$SUSPENDED" -eq 0 ]; then
          notify-send -u critical -t 0 "BATTERY CRITICAL: ''${capacity}%" "Hibernating NOW"
          sleep 2
          SUSPENDED=1
          loginctl hibernate
        elif [ "$capacity" -le 10 ] && [ "$NOTIFIED_10" -eq 0 ]; then
          notify-send -u critical -t 0 "BATTERY: ''${capacity}%" "Plug in immediately or hibernating at 5%"
          NOTIFIED_10=1
        elif [ "$capacity" -le 15 ] && [ "$NOTIFIED_15" -eq 0 ]; then
          notify-send -u critical -t 10000 "BATTERY: ''${capacity}%" "Find a charger"
          NOTIFIED_15=1
        elif [ "$capacity" -le 25 ] && [ "$NOTIFIED_25" -eq 0 ]; then
          notify-send -u normal -t 10000 "BATTERY: ''${capacity}%" "Running low"
          NOTIFIED_25=1
        fi

        # Poll faster when battery is low
        if [ -n "$capacity" ] && [ "$capacity" -le 10 ]; then
          sleep 10
        else
          sleep "$INTERVAL"
        fi
      done
    '';
  };
}
