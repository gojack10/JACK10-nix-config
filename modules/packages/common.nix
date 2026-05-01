{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Terminal & Shell
    zsh
    fzf
    lf

    # Media
    yt-dlp

    # Dev tools
    fastfetch
    htop
    neovim
    ripgrep
    fd
    jq
    tree
  ];
}
