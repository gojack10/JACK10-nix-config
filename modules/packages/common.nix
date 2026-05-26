{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Terminal & Shell
    zsh
    fzf
    lf

    # Dev tools
    fastfetch
    htop
    neovim
    mpv
    ripgrep
    fd
    jq
    tree
    git-filter-repo
  ];
}
