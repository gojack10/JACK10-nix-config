{ config, pkgs, lib, ... }:

let
  src = builtins.path {
    name = "deepwork-src";
    path = /Users/jack/git/deepwork;
  };

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
