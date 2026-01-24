{ config, pkgs, ... }:

{
  home.file.".config/lf/lfrc".text = ''
    # Basic settings
    set hidden true
    set icons true
    set ignorecase true

    # Set nvim as default editor
    set editor nvim

    # Delete with confirmation (works with visual selection)
    cmd delete ''${{
      set -f
      printf "Delete ''$fx? [y/N] "
      read ans
      [ "''$ans" = "y" ] && rm -rf ''$fx
    }}

    # Custom open command - uses mime-type to decide handler
    cmd open ''${{
      case $(file --mime-type -Lb $f) in
        # JSON files open in browser
        application/json)
          xdg-open $f ;;
        # Text-based files open in nvim
        text/*|application/javascript|application/xml|application/x-shellscript|application/x-perl|application/x-ruby|application/x-python|application/x-php|inode/x-empty)
          nvim $f ;;
        # Everything else (images, binaries, PDFs, etc.) use system default
        *)
          xdg-open $f ;;
      esac
    }}

    # Bindings
    map x delete
    map D delete

    # Clear selection after paste
    map p :paste; clear

    map <enter> open
    map o open
    map <esc> unselect
  '';
}
