{
  description = "Jack's home-manager config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Machine-specific settings
      defaults = {
        fontSize = 11.0;
        useSystemSway = true;
      };

      machines = {
        litetop = defaults // { fontSize = 9.5; };
        "10top" = defaults;
        desktop = defaults;
      };

      mkHome = hostname: settings: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit hostname;
          inherit (settings) fontSize useSystemSway;
        };
        modules = [ ./home.nix ];
      };

    in {
      homeConfigurations = builtins.mapAttrs mkHome machines;
    };
}
