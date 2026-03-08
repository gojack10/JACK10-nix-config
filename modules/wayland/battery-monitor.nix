{ config, pkgs, ... }:

{
  home.file.".local/bin/battery-monitor" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Battery monitor: notifications at 15%, 10%, 5% and auto-suspend at 3%
      # Also logs capacity every 5 minutes to ~/.local/share/battery.log

      INTERVAL=30
      NOTIFIED_15=0
      NOTIFIED_10=0
      NOTIFIED_5=0
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
          echo "$(date '+%Y-%m-%d %H:%M:%S') ${capacity}% ${status} ${energy_now}uWh" >> "$LOG_FILE"
          LOG_COUNTER=0
          # Keep log under 10000 lines
          if [ "$(wc -l < "$LOG_FILE")" -gt 10000 ]; then
            tail -5000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
          fi
        fi

        # Reset flags when charging
        if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
          NOTIFIED_15=0
          NOTIFIED_10=0
          NOTIFIED_5=0
          SUSPENDED=0
          sleep "$INTERVAL"
          continue
        fi

        if [ "$capacity" -le 3 ] && [ "$SUSPENDED" -eq 0 ]; then
          notify-send -u critical -t 0 "BATTERY CRITICAL: ''${capacity}%" "Suspending NOW"
          sleep 2
          SUSPENDED=1
          sudo zzz
        elif [ "$capacity" -le 5 ] && [ "$NOTIFIED_5" -eq 0 ]; then
          notify-send -u critical -t 0 "BATTERY: ''${capacity}%" "Plug in immediately or suspending at 3%"
          NOTIFIED_5=1
        elif [ "$capacity" -le 10 ] && [ "$NOTIFIED_10" -eq 0 ]; then
          notify-send -u critical -t 10000 "BATTERY: ''${capacity}%" "Find a charger"
          NOTIFIED_10=1
        elif [ "$capacity" -le 15 ] && [ "$NOTIFIED_15" -eq 0 ]; then
          notify-send -u normal -t 10000 "BATTERY: ''${capacity}%" "Running low"
          NOTIFIED_15=1
        fi

        sleep "$INTERVAL"
      done
    '';
  };
}
