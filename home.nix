{ config, pkgs, lib, settings, ... }:

{
  home.username = settings.username;
  home.homeDirectory = settings.homeDirectory;
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # Fontconfig is Linux-specific (macOS uses its own font system)
  fonts.fontconfig = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font Mono" "Symbols Nerd Font Mono" ];
      emoji = [ "Noto Color Emoji" ];
    };
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

  home.file.".local/share/JACK10-nix-config/bg.png" = lib.mkIf pkgs.stdenv.isLinux {
    source = ./bg.png;
  };

  # Nix settings (enable flakes). Bootstrap may create this file before the
  # first activation, so force Home Manager to take ownership afterwards.
  xdg.configFile."nix/nix.conf".force = true;

  nix = {
    package = pkgs.nix;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
}
