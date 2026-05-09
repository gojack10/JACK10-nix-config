{ config, pkgs, ... }:

let
  pypi-json = builtins.fetchurl {
    url = "https://pypi.org/pypi/huggingface_hub/json";
  };
in

{
  home.packages = with pkgs; [
    # Terminal & Shell
    zsh
    fzf
    lf

    # Dev tools
    fastfetch
    (python3Packages.huggingface-hub.overrideAttrs (_: let
      pypi = builtins.fromJSON (builtins.readFile pypi-json);
    in rec {
      version = pypi.info.version;
      src = builtins.fetchurl {
        url = "https://files.pythonhosted.org/packages/source/h/huggingface_hub/huggingface_hub-${version}.tar.gz";
      };
    }))
    htop
    neovim
    ripgrep
    fd
    jq
    tree
    git-filter-repo
  ];
}
