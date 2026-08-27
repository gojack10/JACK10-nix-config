{ config, pkgs, lib, settings, ... }:

let
  isNixOS = settings.isNixOS or false;
in {
  nixpkgs.config = lib.mkIf (!isNixOS) {
    allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "brave"
      "zoom"
    ];
  };

  home.packages = (with pkgs; [
    # Fonts (macOS has system emoji, Linux needs these)
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    font-awesome
    noto-fonts
    noto-fonts-color-emoji

    # Wayland & Desktop
    waybar
    wofi
    bemenu
    mako
    libnotify
    swaybg
    wl-clipboard
    grim
    slurp
    swappy
    brightnessctl
    wev
    dconf
    gsettings-desktop-schemas
    zenity

    # Terminal
    foot
    xdg-utils
    swayimg

    # Audio
    pavucontrol

    # Bluetooth
    bluetuith
  ]) ++ lib.optionals (!isNixOS) (with pkgs; [
    brave
    zoom-us
  ]);
}
