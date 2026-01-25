{ config, pkgs, fontSize, ... }:

{
  home.file.".config/foot/foot.ini".text = ''
    [main]
    font=JetBrainsMono Nerd Font Mono:size=${toString fontSize}
    pad=8x8

    [colors]
    background=0f0f0f
    foreground=d0d0d0

    regular0=0f0f0f
    regular1=ff5555
    regular2=5fff87
    regular3=ffff5f
    regular4=5fafff
    regular5=ff87ff
    regular6=5fd7ff
    regular7=d0d0d0

    bright0=8a8a8a
    bright1=ff5555
    bright2=5fff87
    bright3=ffff5f
    bright4=5fafff
    bright5=ff87ff
    bright6=5fd7ff
    bright7=ffffff
  '';
}
