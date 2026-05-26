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
      # Machine-specific settings
      # Each machine has a `system` field and optional font/sway overrides.
      linuxDefaults = {
        system = "x86_64-linux";
        username = "jack";
        homeDirectory = "/home/jack";
        gitName = "jack";
        gitEmail = "gojack10@gmail.com";
        fontSize = 11.0;
        fontSizeFoot = 11.5;
        fontSizeWaybar = 11.0;
        useSystemSway = true;
      };

      darwinDefaults = {
        system = "aarch64-darwin";
        username = "jack";
        homeDirectory = "/Users/jack";
        gitName = "jack";
        gitEmail = "gojack10@gmail.com";
        fontSize = 11.0;
        fontSizeFoot = 11.5;
        fontSizeWaybar = 11.0;
        useSystemSway = true;
      };

      machines = {
        # Linux hosts
        litetop = linuxDefaults // { fontSize = 9.5; fontSizeWaybar = 9.5; };
        "10top" = linuxDefaults // { fontSizeWaybar = 11.5; };
        desktop = linuxDefaults;
        # Darwin hosts
        m2-air = darwinDefaults;
        m5-max = darwinDefaults;
        work-mac = darwinDefaults // {
          username = "jack.tenbosch";
          homeDirectory = "/Users/jack.tenbosch";
          gitName = null;
          gitEmail = null;
        };
      };

      # Modules shared across all platforms
      sharedModules = [
        ./home.nix
        ./modules/packages/bootstrap-tools.nix
        ./modules/packages/common.nix
        ./modules/packages/notion-cli.nix
        ./modules/packages/salesforce-cli.nix
        ./modules/scripts.nix
        ./modules/shell/zsh.nix
        ./modules/shell/tmux.nix
        ./modules/shell/git.nix
        ./modules/shell/lf.nix
        ./modules/editor/nvim.nix
      ];

      # Linux-only modules
      linuxModules = [
        ./modules/packages/linux.nix
        ./modules/linux/desktop.nix
        ./modules/linux/fbterm.nix
        ./modules/wayland/sway.nix
        ./modules/wayland/waybar.nix
        ./modules/wayland/foot.nix
        ./modules/wayland/wofi.nix
        ./modules/wayland/mako.nix
        ./modules/wayland/mouse.nix
        ./modules/wayland/battery-monitor.nix
      ];

      # Darwin-only modules
      darwinModules = [
        ./modules/packages/darwin.nix
        ./modules/packages/deepwork.nix
        ./modules/packages/ghostty.nix
        ./modules/darwin/defaults.nix
        ./modules/darwin/fan.nix
        ./modules/darwin/omlx.nix
      ];

      mkHome = hostname: settings:
        let
          isLinux = settings.system == "x86_64-linux";
          pkgs = nixpkgs.legacyPackages.${settings.system};
          platformModules = if isLinux then linuxModules else darwinModules;
        in home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit hostname settings;
            inherit (settings) fontSize fontSizeFoot fontSizeWaybar useSystemSway;
          };
          modules = sharedModules ++ platformModules;
        };

    in {
      homeConfigurations = builtins.mapAttrs mkHome machines;
    };
}
