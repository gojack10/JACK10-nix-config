{ pkgs, ... }:

{
  # Keep this profile small: desktop and hardware packages come from Debian.
  home.packages = with pkgs; [
    zsh
    fzf
    lf
    fastfetch
    htop
    neovim
    ripgrep
    fd
    jq
    tree
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
  ];
}
