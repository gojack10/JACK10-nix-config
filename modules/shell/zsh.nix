{ config, pkgs, ... }:

{
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
      open = "xdg-open";
      ts = "tmux attach \\; choose-tree -NNs";
      claudeyolo = "claude --dangerously-skip-permissions";
      rsync = "rsync -ah --info=progress2 --no-i-r --stats";
      fastfetch = "fastfetch --logo-position top";
      brave-update = "cd ~/void-packages && git -C ./srcpkgs/brave-bin pull && ./xbps-src pkg brave-bin && sudo xbps-install -R hostdir/binpkgs -u brave-bin && cd -";
      # Power management (Void Linux)
      zzz = "echo gn && sudo /usr/bin/zzz > /dev/null 2>&1 && echo 'im up bro'";
      bye = "echo cya && sudo poweroff";
      rrr = "echo 'ok brb' && sudo reboot";
      fixnet = "echo 'Restarting iwd...' && sudo sv restart iwd && echo 'Done'";
    };

    # .zprofile - runs on login shell (XDG needed before sway starts)
    profileExtra = ''
      # XDG_RUNTIME_DIR for Wayland/Sway
      if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR=/tmp/$(id -u)-runtime-dir
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
      fi

      # Source home-manager session variables (GTK_USE_PORTAL, etc.)
      . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"

      # Fix PATH order - /usr/bin before nix paths (fixes dlopen issues with libclang)
      export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin"
    '';

    initContent = ''
      # home-manager update
      alias hmu="nix flake update --flake ~/.config/home-manager"

      # home-manager switch helper
      hms() {
        local flake="$HOME/.config/home-manager"
        local hosts=$(nix eval "$flake#homeConfigurations" --apply 'x: builtins.attrNames x' 2>/dev/null | tr -d '[]"' | tr ' ' '\n' | grep -v '^$')

        if [[ -z "$1" ]]; then
          echo "Usage: hms <hostname>"
          echo "Available hosts:"
          echo "$hosts" | sed 's/^/  /'
          return 1
        fi

        if echo "$hosts" | grep -qx "$1"; then
          home-manager switch --flake "$flake#$1"
        else
          echo "Unknown host: $1"
          echo "Available:"
          echo "$hosts" | sed 's/^/  /'
          return 1
        fi
      }

      # Quality of life
      setopt AUTO_CD
      setopt NO_CORRECT
      setopt NO_BEEP
      setopt HIST_VERIFY
      setopt HIST_EXPIRE_DUPS_FIRST

      # mise version manager (if installed)
      [[ -x "$HOME/.local/bin/mise" ]] && eval "$($HOME/.local/bin/mise activate zsh)"

      # Editor
      export EDITOR=nvim
      export VISUAL=nvim

      # Sudo askpass for GUI prompts (enables sudo -A)
      export SUDO_ASKPASS="$HOME/.local/bin/askpass-wofi"

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

      # Fix PATH order - /usr/bin before nix paths (fixes dlopen issues with libclang)
      export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin"
    '';
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # oh-my-zsh custom theme
  home.file.".config/oh-my-zsh-custom/themes/eastwood-custom.zsh-theme".text = ''
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
}
