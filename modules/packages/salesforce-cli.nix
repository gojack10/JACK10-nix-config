{ pkgs, lib, ... }:

let
  version = "2.135.7";

  # Official Salesforce CLI standalone builds.  These include their own Node.js
  # runtime and provide both `sf` and legacy-compatible `sfdx` commands.
  #
  # The upstream URLs are the stable channel, but the fixed-output hashes pin
  # this derivation to the version above.  To update: refresh version and hashes
  # with `nix store prefetch-file <url>` for each platform.
  platformSources = {
    aarch64-darwin = {
      url = "https://developer.salesforce.com/media/salesforce-cli/sf/channels/stable/sf-darwin-arm64.tar.xz";
      hash = "sha256-gpYSEDi+9rUKKg+zhjxs6WZLtX8zYCB2d+qlskIFTFc=";
    };
    x86_64-darwin = {
      url = "https://developer.salesforce.com/media/salesforce-cli/sf/channels/stable/sf-darwin-x64.tar.xz";
      hash = "sha256-V4qn/BpZ+Flv0/PD8iT84EHCXBSmCwc1Iz8m2gUMGzE=";
    };
    x86_64-linux = {
      url = "https://developer.salesforce.com/media/salesforce-cli/sf/channels/stable/sf-linux-x64.tar.xz";
      hash = "sha256-Tpfjf70KTl+pELUTTBxNwzPzz4CKVqkEcZ5T+U/yMqY=";
    };
    aarch64-linux = {
      url = "https://developer.salesforce.com/media/salesforce-cli/sf/channels/stable/sf-linux-arm64.tar.xz";
      hash = "sha256-P51at5ouyG75mwbfsreVCohbq7/CxvYULIJ5zji0Ibw=";
    };
  };

  source = platformSources.${pkgs.stdenv.hostPlatform.system}
    or (throw "salesforce-cli is not packaged for ${pkgs.stdenv.hostPlatform.system}");

  salesforce-cli = pkgs.stdenvNoCC.mkDerivation {
    pname = "salesforce-cli";
    inherit version;

    src = pkgs.fetchurl source;

    nativeBuildInputs = [ pkgs.makeWrapper ]
      ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];

    buildInputs = lib.optionals pkgs.stdenv.isLinux [
      pkgs.stdenv.cc.cc.lib
      pkgs.zlib
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/salesforce-cli $out/bin
      cp -R . $out/share/salesforce-cli/
      patchShebangs $out/share/salesforce-cli/bin

      ln -s $out/share/salesforce-cli/bin/sf $out/bin/sf
      ln -s $out/share/salesforce-cli/bin/sfdx $out/bin/sfdx

      runHook postInstall
    '';

    meta = {
      description = "Salesforce CLI";
      homepage = "https://developer.salesforce.com/tools/salesforcecli";
      license = lib.licenses.bsd3;
      mainProgram = "sf";
      platforms = builtins.attrNames platformSources;
    };
  };
in {
  home.packages = [ salesforce-cli ];
}
