{ config, pkgs, lib, ... }:

{
  home.activation.cloneBrowserHarness =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      target="$HOME/projects/browser-harness"
      if [ ! -d "$target/.git" ]; then
        $DRY_RUN_CMD mkdir -p "$HOME/projects"
        if $DRY_RUN_CMD ${pkgs.git}/bin/git clone --quiet \
              USER_DEFINED_SSH_HOST:git/browser-harness.git "$target"; then
          echo "browser-harness: cloned to $target"
        else
          echo "browser-harness: clone failed (USER_DEFINED_SSH_HOST unreachable?); skipping" >&2
        fi
      fi
    '';
}
