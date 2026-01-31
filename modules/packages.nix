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
    # wl-screenrec - use system wf-recorder instead (Nix binary can't use system VAAPI)
    brightnessctl
    wev           # wayland event viewer (debug keybindings)
    xdg-desktop-portal      # portal base
    xdg-desktop-portal-wlr  # portal backend for sway (screen capture)
    xdg-desktop-portal-gtk  # portal backend for file dialogs
    dconf                   # GTK settings backend (needed for portal dark theme)
    gsettings-desktop-schemas  # schemas for GTK portal

    # Mouse/input tools
    zenity        # simple GUI dialogs for scripts

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
    jq            # JSON processor

    # Audio - use system pipewire/wireplumber (Nix versions can't access system drivers)
    pavucontrol       # volume control (works with PipeWire)

    # Fonts
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only   # fallback for any missing NF glyphs
    font-awesome
    noto-fonts                # sans-serif UI font
    noto-fonts-color-emoji    # emoji support
  ];
}
