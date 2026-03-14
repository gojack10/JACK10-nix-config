{ config, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    prefix = "C-Space";
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    terminal = "tmux-256color";
    keyMode = "vi";
    extraConfig = ''
      # Clipboard
      set -as terminal-features ',*:clipboard'
      set -g set-clipboard on
      set -g allow-passthrough on
      setw -g pane-base-index 1
      set -g renumber-windows on
      set -g repeat-time 600

      # Copy mode bindings
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi Escape send-keys -X cancel

      # Pane navigation (hjkl)
      bind -r h select-pane -L
      bind -r j select-pane -D
      bind -r k select-pane -U
      bind -r l select-pane -R

      # Resize panes (HJKL)
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      # Splits
      bind | split-window -h -c "#{pane_current_path}"
      bind \\ split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      # Quick actions
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded"
      bind x kill-pane
      bind X kill-window
      bind s choose-tree -NNs

      # F12: toggle between local (default) and passthrough
      # Passthrough: all keys go to inner/remote tmux
      # Local: prefix works on this tmux instance
      bind -T off F12 \
        set prefix C-Space \;\
        set key-table root \;\
        refresh-client -S
      bind -T root F12 \
        set prefix None \;\
        set key-table off \;\
        refresh-client -S

      # Start in local mode (prefix works on this tmux instance)
      # Press F12 to toggle to passthrough mode

      # Pane pip indicator (bottom-left of active pane only)
      set -g pane-border-status bottom
      set -g pane-border-style 'fg=white'
      set -g pane-active-border-style 'fg=white'
      set -g pane-border-format '#{?pane_active,#[fg=green] ● #[fg=white],}'

      # Status bar (basic 8 colors for TTY/framebuffer compatibility)
      set -g status-style 'bg=black fg=white'
      set -g status-left '#[fg=white] #S '
      set -g status-left-length 20
      set -g status-right-length 100
      set -g status-right '#{?#{==:#{client_key_table},off},#[fg=green]PASS#[fg=white],LOCAL} | #(~/.local/bin/tmux-status)'
      set -g status-interval 5
      set -g message-style 'bg=black fg=white'

      # Window tabs
      set -g window-status-format ' #I:#W '
      set -g window-status-current-format '#[fg=green] #I:#W #[fg=white]'
      set -g window-status-separator ""
    '';
  };

  home.file.".local/bin/tmux-status" = {
    executable = true;
    text = ''
      #!/bin/sh

      # CPU (delta between runs via /tmp cache)
      prev=/tmp/.tmux-cpu-prev
      curr=$(awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)
      if [ -f "$prev" ]; then
        read pu pn ps pi pw pq psi < "$prev"
        set -- $curr
        idle=$(( ($4 - pi) + ($5 - pw) ))
        total=$(( ($1-pu) + ($2-pn) + ($3-ps) + ($4-pi) + ($5-pw) + ($6-pq) + ($7-psi) ))
        if [ "$total" -gt 0 ]; then
          cpu=$(( (total - idle) * 100 / total ))
        else
          cpu=0
        fi
      else
        cpu="-"
      fi
      echo "$curr" > "$prev"

      # Memory
      mem=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.1f", (t-a)/1048576}' /proc/meminfo)

      # Battery
      bat=""
      cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
      bstat=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)
      if [ "$bstat" = "Full" ]; then
        bat="FULL"
      elif [ "$bstat" = "Charging" ]; then
        bat="#[fg=green]CHG $cap%#[fg=white]"
      elif [ -n "$cap" ]; then
        if [ "$cap" -le 10 ] 2>/dev/null; then
          bat="#[bg=red,fg=black] BAT $cap% #[bg=black,fg=white]"
        elif [ "$cap" -le 25 ] 2>/dev/null; then
          bat="#[bg=yellow,fg=black] BAT $cap% #[bg=black,fg=white]"
        else
          bat="BAT $cap%"
        fi
      fi

      # Clock (matches waybar format)
      clk=$(date '+%a %Y-%m-%d %H:%M:%S' | sed 's/^[^ ]*/\U&/')

      if [ -n "$bat" ]; then
        printf "CPU %s%% | MEM %sG | %s | %s" "$cpu" "$mem" "$bat" "$clk"
      else
        printf "CPU %s%% | MEM %sG | %s" "$cpu" "$mem" "$clk"
      fi
    '';
  };
}
