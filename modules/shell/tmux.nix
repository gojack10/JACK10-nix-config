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
      set -g status-interval 1
      set -g message-style 'bg=black fg=white'

      # Two status lines
      set -g status 2

      # Line 0: session+windows left, stats+date right
      set -g status-format[0] '#[align=left fg=white] #S #{W:#{?window_active,#[fg=green] #I:#W #[fg=white], #I:#W }}#[align=right fg=white]#{?#{==:#{client_key_table},off},#[fg=green]PASS#[fg=white],LOCAL} | #(~/.local/bin/tmux-status) '

      # Line 1: deepwork centered
      set -g status-format[1] '#[align=centre fg=white]#(~/.local/bin/deepwork-status)'
    '';
  };

  home.file.".local/bin/deepwork-status" = {
    executable = true;
    text = ''
      #!/bin/sh
      DW=$(~/.local/bin/deepwork status 2>/dev/null) || DW="Ready"
      # Cache fbterm check (terminal won't change mid-session)
      cache=/tmp/.tmux-is-fbterm
      if [ ! -f "$cache" ]; then
        tmux display-message -p '#{client_termname}' > "$cache"
      fi
      if [ "$(cat "$cache")" = "fbterm" ]; then
        echo "$DW" | sed 's/󰔟/[DW]/g'
      else
        echo "$DW"
      fi
    '';
  };

  home.file.".local/bin/tmux-status" = {
    executable = true;
    text = ''
      #!/bin/sh

      # Network (ethernet > wifi > disconnected)
      net=""
      if ip link show enp4s0 2>/dev/null | grep -q 'state UP'; then
        net="ETH"
      elif ${pkgs.iwd}/bin/iwctl station wlp0s20f3 show 2>/dev/null | grep -q 'Connected'; then
        ssid=$(${pkgs.iwd}/bin/iwctl station wlp0s20f3 show 2>/dev/null | grep 'Connected network' | sed 's/.*Connected network[[:space:]]*//; s/[[:space:]]*$//')
        net="$ssid"
      else
        net="DISCONNECTED"
      fi

      # CPU (delta between runs via /tmp cache)
      prev=/tmp/.tmux-cpu-prev
      # Read /proc/stat with shell builtins
      read label cu cn cs ci cw cq csi _ < /proc/stat
      curr="$cu $cn $cs $ci $cw $cq $csi"
      if [ -f "$prev" ]; then
        read pu pn ps pi pw pq psi < "$prev"
        idle=$(( (ci - pi) + (cw - pw) ))
        total=$(( (cu-pu) + (cn-pn) + (cs-ps) + (ci-pi) + (cw-pw) + (cq-pq) + (csi-psi) ))
        if [ "$total" -gt 0 ]; then
          cpu=$(( (total - idle) * 100 / total ))
        else
          cpu=0
        fi
      else
        cpu="-"
      fi
      echo "$curr" > "$prev"

      # Memory (shell builtins, no awk)
      while read key val _; do
        case "$key" in
          MemTotal:) mt=$val ;;
          MemAvailable:) ma=$val; break ;;
        esac
      done < /proc/meminfo
      used_mb=$(( (mt - ma) / 1024 ))
      mem_int=$(( used_mb / 1024 ))
      mem_dec=$(( (used_mb % 1024) * 10 / 1024 ))
      mem="$mem_int.$mem_dec"

      # Battery (read builtins)
      bat=""
      cap=""
      bstat=""
      read cap < /sys/class/power_supply/BAT0/capacity 2>/dev/null
      read bstat < /sys/class/power_supply/BAT0/status 2>/dev/null
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

      # Date (shell builtin, %^a for uppercase day)
      dt=$(date "+%^a %Y-%m-%d %H:%M:%S")

      if [ -n "$bat" ]; then
        printf "%s | CPU %s%% | MEM %sG | %s | %s" "$net" "$cpu" "$mem" "$bat" "$dt"
      else
        printf "%s | CPU %s%% | MEM %sG | %s" "$net" "$cpu" "$mem" "$dt"
      fi
    '';
  };
}
