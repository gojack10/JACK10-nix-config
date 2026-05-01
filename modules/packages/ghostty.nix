{ config, pkgs, ... }:

let fontSizeGhostty = 14; in
{
  home.file.".config/ghostty/config".text = ''
    # Font
    font-family = JetBrainsMono Nerd Font Mono
    font-size = ${toString fontSizeGhostty}

    # Padding
    window-padding-x = 8
    window-padding-y = 8

    # Colors
    background = 0f0f0f
    foreground = d0d0d0

    palette = 0=0f0f0f
    palette = 1=ff5555
    palette = 2=5fff87
    palette = 3=ffff5f
    palette = 4=5fafff
    palette = 5=ff87ff
    palette = 6=5fd7ff
    palette = 7=d0d0d0
    palette = 8=8a8a8a
    palette = 9=ff5555
    palette = 10=5fff87
    palette = 11=ffff5f
    palette = 12=5fafff
    palette = 13=ff87ff
    palette = 14=5fd7ff
    palette = 15=ffffff

    # Cursor
    cursor-style = block
    cursor-style-blink = false

    # Shell integration: keep everything except the prompt cursor override
    shell-integration-features = no-cursor
  '';
}
