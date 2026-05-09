{ pkgs, lib, ... }:

# macOS fan control. Builds the smc userspace client (scripts/system/smc.c) as
# a Nix derivation and installs the `fan` wrapper to ~/.local/bin/fan.
#
# Mirrors the Linux ThinkPad fan-toggle pattern in modules/shell/tmux.nix, but
# uses AppleSMC IOKit instead of /proc/acpi/ibm/fan. See scripts/system/smc.c
# for the full key reference; the short version:
#   F0md/F1md = mode (0=auto, 1=manual)
#   F0Tg/F1Tg = target RPM (writes above F0Mx still saturate PWM at 100%)
#
# Writes require root; the wrapper invokes `sudo smc write ...` directly.

let
  smc = pkgs.stdenv.mkDerivation {
    pname = "smc";
    version = "0.1.0";

    src = builtins.path {
      path = ../../scripts/system/smc.c;
      name = "smc.c";
    };
    dontUnpack = true;

    buildPhase = ''
      runHook preBuild
      $CC -O2 -Wall -framework IOKit -framework CoreFoundation "$src" -o smc
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 smc $out/bin/smc
      runHook postInstall
    '';

    meta = {
      description = "Apple Silicon AppleSMC userspace client (read/write/list/info)";
      platforms = lib.platforms.darwin;
    };
  };
in
{
  home.packages = [ smc ];

  home.file.".local/bin/fan" = {
    source = ../../scripts/system/fan-mac;
    executable = true;
    force = true;
  };
}
