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
    '';
  };
}
