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
    git
    ripgrep
    fd
    jq

    # Fonts
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    font-awesome
    noto-fonts
    noto-fonts-color-emoji
  ];
}
