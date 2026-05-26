{ pkgs, lib, ... }:

let
  version = "6.3.2";

  # @coastal-programs/notion-cli is the Notion CLI that is explicitly built
  # for automation/AI agents.  It is published to npm as small per-platform
  # binary packages, so package the binary directly instead of relying on a
  # mutable npm global install.
  platformSources = {
    aarch64-darwin = {
      url = "https://registry.npmjs.org/@coastal-programs/notion-cli-darwin-arm64/-/notion-cli-darwin-arm64-${version}.tgz";
      hash = "sha512-7oyfXfh5yVszuYqITeANzZxta+DXcprlEAkAVcczr2vHF5MsVyVj0FoRps8NhAlQCmU4qTF5AlbgZcxHFFyybQ==";
    };
    x86_64-darwin = {
      url = "https://registry.npmjs.org/@coastal-programs/notion-cli-darwin-x64/-/notion-cli-darwin-x64-${version}.tgz";
      hash = "sha512-LKEKEx7T+BzlDJbZl7BnK2h3oecc1Q9uKRdwPZjZKewmaZU0Umj3jX2qdmJOlvu/G2HQNRIvn6LBU/fQ8PlyTA==";
    };
    x86_64-linux = {
      url = "https://registry.npmjs.org/@coastal-programs/notion-cli-linux-x64/-/notion-cli-linux-x64-${version}.tgz";
      hash = "sha512-9NhKm3mrxZ5kZeEAtE6G2jy99he6HcsCujJESUCF5m52uVkuu7alKJvwaqTlJeTJwt27RpFscwJsYw8iaqKgOQ==";
    };
    aarch64-linux = {
      url = "https://registry.npmjs.org/@coastal-programs/notion-cli-linux-arm64/-/notion-cli-linux-arm64-${version}.tgz";
      hash = "sha512-tc3Yglt+Ek1MxgtfoQmAWmzNQ6aNIRppsqikkmz3xK0j+2dClqSDd78fNci4G14lRaHWT34Oq5DB/yUblKSc9g==";
    };
  };

  source = platformSources.${pkgs.stdenv.hostPlatform.system}
    or (throw "notion-cli is not packaged for ${pkgs.stdenv.hostPlatform.system}");

  notion-cli = pkgs.stdenvNoCC.mkDerivation {
    pname = "notion-cli";
    inherit version;

    src = pkgs.fetchurl source;

    nativeBuildInputs = lib.optionals pkgs.stdenv.isLinux [
      pkgs.autoPatchelfHook
    ];

    buildInputs = lib.optionals pkgs.stdenv.isLinux [
      pkgs.stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 bin/notion-cli $out/bin/notion-cli
      runHook postInstall
    '';

    meta = {
      description = "Unofficial Notion CLI optimized for automation and AI agents";
      homepage = "https://github.com/Coastal-Programs/notion-cli";
      license = lib.licenses.mit;
      mainProgram = "notion-cli";
      platforms = builtins.attrNames platformSources;
    };
  };
in {
  home.packages = [ notion-cli ];
}
