{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Fonts (nerd fonts install to nix profile; macOS apps can find them)
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
  ];
}
