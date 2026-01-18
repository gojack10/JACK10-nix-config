{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Wayland & Desktop (sway added by wayland.windowManager.sway.enable)
    waybar
    wofi          # rofi replacement for wayland
    mako          # notification daemon
    swaybg        # wallpaper
    swaylock      # lock screen
    swayidle      # idle management
    wl-clipboard  # clipboard
    grim          # screenshot
    slurp         # region selection
    brightnessctl

    # Terminal & Shell
    foot          # lightweight wayland-native terminal
    zsh
    fzf

    # Dev tools
    neovim
    git
    ripgrep
    fd

    # System
    networkmanagerapplet
    pavucontrol
    pulseaudio  # for pactl

    # Fonts
    nerd-fonts.jetbrains-mono
    font-awesome
  ];
}
