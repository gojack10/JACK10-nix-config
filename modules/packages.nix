{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Wayland & Desktop (sway added by wayland.windowManager.sway.enable)
    waybar
    wofi          # rofi replacement for wayland
    bemenu        # simpler dmenu for wayland (used for askpass)
    mako          # notification daemon
    swaybg        # wallpaper
    wl-clipboard  # clipboard
    grim          # screenshot
    slurp         # region selection
    swappy        # screenshot annotation
    brightnessctl
    xdg-desktop-portal      # portal base
    xdg-desktop-portal-wlr  # portal backend for sway (screen capture)
    xdg-desktop-portal-gtk  # portal backend for file dialogs

    # Terminal & Shell
    foot          # lightweight wayland-native terminal
    zsh
    fzf
    lf            # terminal file manager (vim-like)
    xdg-utils     # xdg-open for lf
    swayimg       # simple image viewer for sway

    # Dev tools
    neovim
    git
    ripgrep
    fd

    # Audio (PipeWire replaces PulseAudio, also enables portal screen capture)
    pipewire
    wireplumber       # PipeWire session manager
    pavucontrol       # volume control (works with PipeWire)

    # Fonts
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only   # fallback for any missing NF glyphs
    font-awesome
    noto-fonts                # sans-serif UI font
    noto-fonts-color-emoji    # emoji support
  ];
}
