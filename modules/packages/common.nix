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
    neovim
    ripgrep
    fd
    jq
  ];
}
