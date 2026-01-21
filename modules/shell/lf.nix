{ config, pkgs, ... }:

{
  home.file.".config/lf/lfrc".text = ''
    # Basic settings
    set hidden true
    set icons true
    set ignorecase true

    # Delete with confirmation (works with visual selection)
    cmd delete ''${{
      set -f
      printf "Delete ''$fx? [y/N] "
      read ans
      [ "''$ans" = "y" ] && rm -rf ''$fx
    }}

    # Bindings
    map x delete
    map D delete

    # Clear selection after paste
    map p :paste; clear

    # Open files with xdg-open
    cmd open ''${{
      xdg-open "''$f" >/dev/null 2>&1 &
    }}

    map <enter> open
    map o open
  '';
}
