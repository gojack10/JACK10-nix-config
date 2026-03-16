{ config, pkgs, lib, ... }:

let
  opener = if pkgs.stdenv.isDarwin then "open" else "xdg-open";
in
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

    # Custom open command - extension first, then mime-type fallback
    cmd open ''${{
      # Check extension first (more reliable for code)
      case "$f" in
        # Code/text files -> nvim
        *.nix|*.sh|*.bash|*.zsh|*.fish|\
        *.py|*.rb|*.pl|*.lua|*.go|*.rs|*.c|*.h|*.cpp|*.hpp|*.cc|\
        *.js|*.ts|*.jsx|*.tsx|*.mjs|*.cjs|\
        *.java|*.kt|*.scala|*.clj|\
        *.html|*.css|*.scss|*.sass|*.less|\
        *.json|*.yaml|*.yml|*.toml|*.xml|*.csv|\
        *.md|*.markdown|*.txt|*.rst|*.org|\
        *.vim|*.el|*.conf|*.cfg|*.ini|\
        *.sql|*.graphql|*.proto|\
        *.diff|*.patch|\
        *.dockerfile|Dockerfile*|*.containerfile|\
        Makefile|makefile|*.mk|CMakeLists.txt|\
        *.env|*.env.*|.gitignore|.gitattributes)
          nvim "$f" ;;
        # Media -> open with default handler
        *.mp4|*.mkv|*.webm|*.avi|*.mov|*.flv|*.wmv|*.m4v|\
        *.mp3|*.flac|*.ogg|*.wav|*.m4a|*.aac|*.opus|*.wma)
          ${opener} "$f" ;;
        # Images -> open with default handler
        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.svg|*.ico)
          ${opener} "$f" ;;
        # Documents -> open with default handler
        *.pdf|*.epub)
          ${opener} "$f" ;;
        # Fallback to mime-type detection
        *)
          case $(file --mime-type -Lb "$f") in
            text/*|application/json|application/javascript|application/xml|\
            application/x-shellscript|application/x-perl|application/x-ruby|\
            application/x-python|application/x-php|inode/x-empty)
              nvim "$f" ;;
            *)
              ${opener} "$f" ;;
          esac ;;
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
