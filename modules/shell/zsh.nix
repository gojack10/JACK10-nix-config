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

      # Git aliases (replaces oh-my-zsh git plugin)
      g = "git";
      ga = "git add";
      gaa = "git add --all";
      gau = "git add --update";
      gapa = "git add --patch";
      gb = "git branch";
      gbd = "git branch --delete";
      gbD = "git branch --delete --force";
      gba = "git branch --all";
      gbl = "git blame -w";
      gc = "git commit --verbose";
      gca = "git commit --verbose --all";
      gcam = "git commit --all --message";
      gcmsg = "git commit --message";
      gco = "git checkout";
      gcb = "git checkout -b";
      gcp = "git cherry-pick";
      gd = "git diff";
      gds = "git diff --staged";
      gf = "git fetch";
      gl = "git pull";
      glog = "git log --oneline --decorate --graph";
      glg = "git log --stat";
      glgg = "git log --graph";
      gm = "git merge";
      gp = "git push";
      grb = "git rebase";
      grbi = "git rebase --interactive";
      grhh = "git reset --hard";
      gss = "git status --short";
      gst = "git status";
      gsta = "git stash push";
      gstp = "git stash pop";
    };

    # .zprofile - runs on login shell (XDG needed before sway starts)
    profileExtra = ''
      # XDG_RUNTIME_DIR for Wayland/Sway
      if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR=/tmp/$(id -u)-runtime-dir
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
      fi

      # Fix PATH order - /usr/bin before nix paths (fixes dlopen issues with libclang)
      export PATH="$HOME/.opencode/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin"
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
      export PATH="$HOME/.opencode/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin"

      # Git helper functions (replaces oh-my-zsh git lib)
      git_main_branch() {
        command git rev-parse --git-dir &>/dev/null || return
        local ref
        for ref in refs/{heads,remotes/{origin,upstream}}/{main,trunk,mainline,default,stable,master}; do
          if command git show-ref -q --verify "$ref"; then
            echo "''${ref:t}"
            return 0
          fi
        done
        echo master
      }

      gcm() { git checkout "$(git_main_branch)"; }

      # Prompt - replaces oh-my-zsh eastwood-custom theme
      autoload -Uz colors && colors

      _git_prompt_info() {
        local branch
        branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null) || \
          branch=$(command git rev-parse --short HEAD 2>/dev/null) || return
        local dirty=""
        if [[ -n $(command git status --porcelain --ignore-submodules=dirty 2>/dev/null | tail -n 1) ]]; then
          dirty="%{$fg[red]%}*%{$reset_color%}"
        fi
        echo "''${dirty}%{$fg[green]%}[''${branch}]%{$reset_color%}"
      }

      setopt PROMPT_SUBST
      PROMPT='%F{green}%n@%m%f $(_git_prompt_info)%{$fg[cyan]%}[%~% ]%{$reset_color%}%B$%b '
    '';
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}
