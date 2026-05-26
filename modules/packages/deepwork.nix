{ config, pkgs, lib, ... }:

let
  # Vendored so the flake is self-contained on new machines.
  src = ./deepwork-src;

  deepwork = pkgs.rustPlatform.buildRustPackage {
    pname = "deepwork";
    version = "0.1.0";

    inherit src;

    cargoLock = {
      lockFile = src + "/Cargo.lock";
    };

    doCheck = false;
  };
in
{
  home.packages = [ deepwork ];
}
