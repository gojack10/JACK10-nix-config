{ config, pkgs, ... }:

let
  # Check /etc/hostname for reliable hostname detection
  hostnameFile = builtins.readFile /etc/hostname;
  hostname = builtins.replaceStrings ["\n"] [""] hostnameFile;
  # Machines that need system sway (non-NixOS with driver issues)
  useSystemSway = builtins.elem hostname [ "litetop" ];
in
{
  home.username = "jack";
  home.homeDirectory = "/home/jack";
  home.stateVersion = "25.11";

  # ══════════════════════════════════════════════════════════════════════════════
  # PACKAGES
  # ══════════════════════════════════════════════════════════════════════════════
  home.packages = with pkgs; [
    # Wayland & Desktop (sway added by wayland.windowManager.sway.enable)
    waybar
    wofi          # rofi replacement for wayland
    mako          # notification daemon
    swaybg        # wallpaper
    swaylock      # lock screen
    swayidle      # idle management
    wl-clipboard  # clipboard
    grim          # screenshot
    slurp         # region selection
    brightnessctl

    # Terminal & Shell
    foot          # lightweight wayland-native terminal
    zsh
    fzf

    # Dev tools
    neovim
    git
    ripgrep
    fd

    # System
    networkmanagerapplet
    pavucontrol
    pulseaudio  # for pactl

    # Fonts
    nerd-fonts.jetbrains-mono
    font-awesome
  ];

  # ══════════════════════════════════════════════════════════════════════════════
  # PROGRAMS
  # ══════════════════════════════════════════════════════════════════════════════

  programs.home-manager.enable = true;

  # ── Tmux ────────────────────────────────────────────────────────────────────
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

  # ── Zsh ─────────────────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;

    plugins = [
      {
        name = "fzf-tab";
        src = pkgs.fetchFromGitHub {
          owner = "Aloxaf";
          repo = "fzf-tab";
          rev = "v1.1.2";
          sha256 = "sha256-Qv8zAiMtrr67CbLRrFjGaPzFZcOiMVEFLg1Z+N6VMhg=";
        };
      }
    ];

    history = {
      size = 100000;
      save = 100000;
      ignoreDups = true;
      ignoreAllDups = true;
      share = true;
      extended = true;
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "fzf" ];
      theme = "eastwood-custom";
      custom = "$HOME/.config/oh-my-zsh-custom";
    };

    shellAliases = {
      ts = "tmux attach \\; choose-tree -NNs";
      claudeyolo = "claude --dangerously-skip-permissions";
      rsync = "rsync -ah --info=progress2 --no-i-r --stats";
      fastfetch = "fastfetch --logo-position top";
    };

    # .zprofile - runs on login shell (XDG needed before sway starts)
    profileExtra = ''
      # XDG_RUNTIME_DIR for Wayland/Sway
      if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR=/tmp/$(id -u)-runtime-dir
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
      fi
    '';

    initExtra = ''
      # Quality of life
      setopt AUTO_CD
      setopt CORRECT
      setopt NO_BEEP
      setopt HIST_VERIFY
      setopt HIST_EXPIRE_DUPS_FIRST

      # PATH
      export PATH="$HOME/.local/bin:$PATH"
      export PATH="$HOME/.nix-profile/bin:$PATH"

      # Editor
      export EDITOR=nvim
      export VISUAL=nvim

      # pbcopy for OSC 52 clipboard (works in tmux, SSH, raw terminal)
      pbcopy() {
        if [[ -n "$TMUX" ]]; then
          local data=$(base64 | tr -d '\n')
          printf '\033Ptmux;\033\033]52;c;%s\007\033\\' "$data"
        elif [[ -n "$SSH_TTY" ]]; then
          local data=$(base64 | tr -d '\n')
          printf '\033]52;c;%s\007' "$data"
        elif command -v /usr/bin/pbcopy &>/dev/null; then
          /usr/bin/pbcopy
        else
          local data=$(base64 | tr -d '\n')
          printf '\033]52;c;%s\007' "$data"
        fi
      }
    '';
  };

  # ── Git ─────────────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    userName = "jack";
    # userEmail = "your@email.com";  # uncomment and set
  };

  # ── fzf ─────────────────────────────────────────────────────────────────────
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # ══════════════════════════════════════════════════════════════════════════════
  # SWAY (Wayland i3)
  # ══════════════════════════════════════════════════════════════════════════════

  wayland.windowManager.sway = {
    enable = true;
    package = if useSystemSway then null else pkgs.sway;
    wrapperFeatures.gtk = true;
    config = {
      modifier = "Mod4";
      terminal = "foot";

      fonts = {
        names = [ "JetBrainsMono Nerd Font" ];
        size = 10.0;
      };

      gaps = {
        inner = 10;
        outer = 6;
        smartBorders = "on";
        smartGaps = true;
      };

      window = {
        border = 2;
        titlebar = false;
      };

      floating = {
        border = 2;
        titlebar = false;
      };

      colors = {
        focused = {
          border = "#6f6f6f";
          background = "#6f6f6f";
          text = "#ffffff";
          indicator = "#6f6f6f";
          childBorder = "#6f6f6f";
        };
        focusedInactive = {
          border = "#3a3a3a";
          background = "#3a3a3a";
          text = "#8a8a8a";
          indicator = "#3a3a3a";
          childBorder = "#3a3a3a";
        };
        unfocused = {
          border = "#3a3a3a";
          background = "#3a3a3a";
          text = "#8a8a8a";
          indicator = "#3a3a3a";
          childBorder = "#3a3a3a";
        };
        urgent = {
          border = "#ff5555";
          background = "#ff5555";
          text = "#ffffff";
          indicator = "#ff5555";
          childBorder = "#ff5555";
        };
      };

      keybindings = let modifier = "Mod4"; in {
        "${modifier}+Return" = "exec foot";
        "${modifier}+d" = "exec wofi --show drun";
        "${modifier}+Shift+q" = "kill";
        "${modifier}+f" = "fullscreen toggle";
        "${modifier}+e" = "layout toggle split";
        "${modifier}+s" = "layout stacking";
        "${modifier}+w" = "layout tabbed";
        "${modifier}+Shift+space" = "floating toggle";
        "${modifier}+Shift+r" = "reload";
        "${modifier}+space" = "scratchpad show";

        # Focus (hjkl)
        "${modifier}+h" = "focus left";
        "${modifier}+j" = "focus down";
        "${modifier}+k" = "focus up";
        "${modifier}+l" = "focus right";

        # Move (Shift+hjkl)
        "${modifier}+Shift+h" = "move left";
        "${modifier}+Shift+j" = "move down";
        "${modifier}+Shift+k" = "move up";
        "${modifier}+Shift+l" = "move right";

        # Workspaces
        "${modifier}+1" = "workspace 1";
        "${modifier}+2" = "workspace 2";
        "${modifier}+3" = "workspace 3";
        "${modifier}+4" = "workspace 4";
        "${modifier}+5" = "workspace 5";
        "${modifier}+6" = "workspace 6";
        "${modifier}+7" = "workspace 7";
        "${modifier}+8" = "workspace 8";
        "${modifier}+9" = "workspace 9";
        "${modifier}+0" = "workspace 10";

        "${modifier}+Shift+1" = "move container to workspace 1";
        "${modifier}+Shift+2" = "move container to workspace 2";
        "${modifier}+Shift+3" = "move container to workspace 3";
        "${modifier}+Shift+4" = "move container to workspace 4";
        "${modifier}+Shift+5" = "move container to workspace 5";
        "${modifier}+Shift+6" = "move container to workspace 6";
        "${modifier}+Shift+7" = "move container to workspace 7";
        "${modifier}+Shift+8" = "move container to workspace 8";
        "${modifier}+Shift+9" = "move container to workspace 9";
        "${modifier}+Shift+0" = "move container to workspace 10";

        # Volume/brightness
        "XF86MonBrightnessUp" = "exec brightnessctl set +5%";
        "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
        "XF86AudioRaiseVolume" = "exec pactl set-sink-volume @DEFAULT_SINK@ +5%";
        "XF86AudioLowerVolume" = "exec pactl set-sink-volume @DEFAULT_SINK@ -5%";
        "XF86AudioMute" = "exec pactl set-sink-mute @DEFAULT_SINK@ toggle";

        # Screenshot
        "Print" = "exec grim -g \"$(slurp)\" - | wl-copy";
      };

      bars = [{
        command = "waybar";
      }];

      startup = [
        { command = "mako"; }
        { command = "nm-applet --indicator"; }
      ];

      input = {
        "type:touchpad" = {
          tap = "enabled";
          natural_scroll = "enabled";
          accel_profile = "adaptive";
          pointer_accel = "0.3";
        };
        "type:keyboard" = {
          repeat_delay = "300";
          repeat_rate = "30";
        };
      };

      output = {
        "*" = {
          bg = "#0f0f0f solid_color";
        };
      };
    };
  };

  # ══════════════════════════════════════════════════════════════════════════════
  # CONFIG FILES
  # ══════════════════════════════════════════════════════════════════════════════

  home.file = {
    # oh-my-zsh custom theme
    ".config/oh-my-zsh-custom/themes/eastwood-custom.zsh-theme".text = ''
      # Customized git status - shows dirty marker before branch name
      git_custom_status() {
        local cb=$(git_current_branch)
        if [ -n "$cb" ]; then
          echo "$(parse_git_dirty)$ZSH_THEME_GIT_PROMPT_PREFIX$(git_current_branch)$ZSH_THEME_GIT_PROMPT_SUFFIX"
        fi
      }

      ZSH_THEME_GIT_PROMPT_PREFIX="%{$reset_color%}%{$fg[green]%}["
      ZSH_THEME_GIT_PROMPT_SUFFIX="]%{$reset_color%}"
      ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[red]%}*%{$reset_color%}"
      ZSH_THEME_GIT_PROMPT_CLEAN=""

      PROMPT='%F{green}%n@%m%f $(git_custom_status)%{$fg[cyan]%}[%~% ]%{$reset_color%}%B$%b '
    '';

    # Waybar config (polybar replacement)
    ".config/waybar/config".text = builtins.toJSON {
      layer = "top";
      position = "top";
      height = 26;
      modules-left = [ "sway/workspaces" "sway/mode" ];
      modules-right = [ "pulseaudio" "cpu" "memory" "network" "battery" "clock" ];

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

      pulseaudio = {
        format = "VOL {volume}%";
        format-muted = "muted";
      };

      clock = {
        format = "{:%Y-%m-%d %H:%M}";
        interval = 1;
      };
    };

    ".config/waybar/style.css".text = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 12px;
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

    # Foot terminal (lightweight wayland terminal)
    ".config/foot/foot.ini".text = ''
      [main]
      font=JetBrainsMono Nerd Font:size=11
      pad=8x8

      [colors]
      background=0f0f0f
      foreground=d0d0d0

      regular0=0f0f0f
      regular1=ff5555
      regular2=5fff87
      regular3=ffff5f
      regular4=5fafff
      regular5=ff87ff
      regular6=5fd7ff
      regular7=d0d0d0

      bright0=8a8a8a
      bright1=ff5555
      bright2=5fff87
      bright3=ffff5f
      bright4=5fafff
      bright5=ff87ff
      bright6=5fd7ff
      bright7=ffffff
    '';

    # Wofi (rofi replacement)
    ".config/wofi/style.css".text = ''
      window {
        background-color: #0f0f0f;
        color: #d0d0d0;
        font-family: "JetBrainsMono Nerd Font";
        font-size: 12px;
      }

      #input {
        background-color: #151515;
        color: #d0d0d0;
        border: none;
        padding: 8px;
      }

      #entry {
        padding: 8px;
      }

      #entry:selected {
        background-color: #6f6f6f;
        color: #ffffff;
      }
    '';

    # Mako notifications
    ".config/mako/config".text = ''
      font=JetBrainsMono Nerd Font 10
      background-color=#0f0f0f
      text-color=#d0d0d0
      border-color=#6f6f6f
      border-size=2
      padding=10
      default-timeout=5000
    '';

    # Neovim config
    ".config/nvim/init.lua".text = ''
      vim.g.mapleader = " "
      vim.opt.clipboard = "unnamedplus"
      vim.opt.number = true
      vim.opt.relativenumber = false
      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      vim.opt.smartindent = true
      vim.opt.termguicolors = true
      vim.opt.signcolumn = "yes"
      vim.opt.updatetime = 250
      vim.opt.scrolloff = 8
      vim.opt.ignorecase = true
      vim.opt.smartcase = true
      vim.opt.wrap = true
      vim.opt.linebreak = true

      -- Bootstrap lazy.nvim
      local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
      if not vim.uv.fs_stat(lazypath) then
        vim.fn.system({ "git", "clone", "--filter=blob:none",
          "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
      end
      vim.opt.rtp:prepend(lazypath)

      require("lazy").setup({
        { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
        { "nvim-telescope/telescope.nvim", branch = "0.1.x",
          dependencies = { "nvim-lua/plenary.nvim" },
          keys = {
            { "<leader>ff", "<cmd>Telescope find_files<cr>" },
            { "<leader>fg", "<cmd>Telescope live_grep<cr>" },
            { "<leader>fb", "<cmd>Telescope buffers<cr>" },
          },
        },
        { "lewis6991/gitsigns.nvim",
          config = function() require("gitsigns").setup() end,
        },
      }, { checker = { enabled = false } })

      -- Colorscheme
      vim.cmd.colorscheme("default")
      local hl = vim.api.nvim_set_hl
      hl(0, "Normal", { bg = "#000000", fg = "#e4e4e4" })
      hl(0, "NormalFloat", { bg = "#0a0a0a", fg = "#e4e4e4" })
      hl(0, "CursorLine", { bg = "#0a0a0a" })
      hl(0, "LineNr", { fg = "#808080" })
      hl(0, "Comment", { fg = "#808080", italic = true })
      hl(0, "String", { fg = "#5fff87" })
      hl(0, "Keyword", { fg = "#ffffff", bold = true })
    '';
  };

  # ══════════════════════════════════════════════════════════════════════════════
  # FONTS
  # ══════════════════════════════════════════════════════════════════════════════
  fonts.fontconfig.enable = true;

  # ══════════════════════════════════════════════════════════════════════════════
  # SESSION VARIABLES
  # ══════════════════════════════════════════════════════════════════════════════
  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    XDG_CURRENT_DESKTOP = "sway";
    XDG_SESSION_TYPE = "wayland";
  };
}
