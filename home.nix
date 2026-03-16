{ config, pkgs, lib, ... }:

{
  home.username = "jack";
  home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/jack" else "/home/jack";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  fonts.fontconfig.enable = true;
  fonts.fontconfig.defaultFonts = {
    monospace = [ "JetBrainsMono Nerd Font Mono" "Symbols Nerd Font Mono" ];
    emoji = [ "Noto Color Emoji" ];
  };

  home.sessionVariables = {
    LANG = "C.UTF-8";
    OPENCODE_DISABLE_SYSTEM_PROMPT = "true";
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.nix-profile/bin"
    "$HOME/.cargo/bin"
  ];

  # Nix settings (enable flakes)
  nix = {
    package = pkgs.nix;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
}
