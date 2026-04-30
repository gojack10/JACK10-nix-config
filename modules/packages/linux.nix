{ config, pkgs, ... }:

{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "zoom"
  ];

  home.packages = with pkgs; [
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

    # Communication
    zoom-us

    # Audio
    pavucontrol

    # Bluetooth
    bluetuith
  ];
}
