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
        # Media -> xdg-open (uses mpv)
        *.mp4|*.mkv|*.webm|*.avi|*.mov|*.flv|*.wmv|*.m4v|\
        *.mp3|*.flac|*.ogg|*.wav|*.m4a|*.aac|*.opus|*.wma)
          xdg-open "$f" ;;
        # Images -> xdg-open (uses swayimg)
        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.svg|*.ico)
          xdg-open "$f" ;;
        # Documents -> xdg-open (uses brave)
        *.pdf|*.epub)
          xdg-open "$f" ;;
        # Fallback to mime-type detection
        *)
          case $(file --mime-type -Lb "$f") in
            text/*|application/json|application/javascript|application/xml|\
            application/x-shellscript|application/x-perl|application/x-ruby|\
            application/x-python|application/x-php|inode/x-empty)
              nvim "$f" ;;
            *)
              xdg-open "$f" ;;
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
