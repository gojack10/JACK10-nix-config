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
        fontSizeFoot = 11.0;
        fontSizeWaybar = 11.0;
        useSystemSway = true;
      };

      machines = {
        litetop = defaults // { fontSize = 9.5; fontSizeFoot = 9.5; fontSizeWaybar = 9.5; };
        "10top" = defaults // { fontSizeFoot = 12.0; fontSizeWaybar = 11.5; };
        desktop = defaults;
      };

      mkHome = hostname: settings: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit hostname;
          inherit (settings) fontSize fontSizeFoot fontSizeWaybar useSystemSway;
        };
        modules = [ ./home.nix ];
      };

    in {
      homeConfigurations = builtins.mapAttrs mkHome machines;
    };
}
