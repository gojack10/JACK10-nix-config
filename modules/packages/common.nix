{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Terminal & Shell
    zsh
    fzf
    lf

    # Dev tools
    fastfetch
    python3Packages.huggingface-hub
    htop
    neovim
    ripgrep
    fd
    jq
    tree
    git-filter-repo
  ];
}
