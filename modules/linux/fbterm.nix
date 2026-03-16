# fbterm - framebuffer terminal with fontconfig support
# System setup (one-time, via xbps):
#   sudo xbps-install fbterm
#   sudo usermod -aG video jack
#   sudo setcap 'cap_sys_tty_config+ep' /usr/bin/fbterm
{ fontSize, ... }:

{
  home.file.".fbtermrc".text = ''
    font-names=JetBrainsMono Nerd Font Mono
    font-size=${toString (builtins.floor (fontSize + 3.5))}
    color-foreground=7
    color-background=0
    cursor-shape=1
    cursor-interval=0
  '';
}
