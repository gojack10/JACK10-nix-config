{ pkgs, lib, ... }:

let
  timer = pkgs.stdenv.mkDerivation {
    pname = "timer";
    version = "0.1.0";

    src = pkgs.fetchFromGitHub {
      owner = "gojack10";
      repo = "timer";
      rev = "a0bc478ec88e6a1794f3a7a203c81343b43936c6";
      hash = "sha256-1K4TA0W/uM4/u2oD+wHBg0FqxGKMBCwFO/Z5URPze6M=";
    };

    installPhase = ''
      make install PREFIX=$out
    '';

    meta = {
      description = "Monochrome terminal countdown with microwave and target-time input";
      homepage = "https://github.com/gojack10/timer";
      license = lib.licenses.mit;
      mainProgram = "timer";
      platforms = lib.platforms.unix;
    };
  };
in {
  home.packages = [ timer ];
}
