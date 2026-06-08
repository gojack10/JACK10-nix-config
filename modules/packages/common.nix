{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Terminal & Shell
    zsh
    fzf
    lf
    autossh

    # Dev tools
    fastfetch
    htop
    neovim
    mpv
    python3
    ripgrep
    fd
    jq
    tree
    git-filter-repo

    # Media tools
    ffmpeg
    yt-dlp
    spotdl
  ];
}
