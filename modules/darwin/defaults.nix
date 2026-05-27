{ config, pkgs, lib, ... }:

{
  # Applies to every Darwin homeConfiguration, including work-mac.
  targets.darwin.defaults.NSGlobalDomain = {
    # Current preferred values discovered with:
    #   defaults read -g KeyRepeat
    #   defaults read -g InitialKeyRepeat
    KeyRepeat = 2;
    InitialKeyRepeat = 10;

    # Make held letter keys repeat too, instead of showing the accent picker.
    ApplePressAndHoldEnabled = false;
  };
}
