{ pkgs, ... }:

let
  nodejs = pkgs.nodejs_24 or pkgs.nodejs;
in
{
  home.packages = with pkgs; [
    git
    gh
    openssh
    rsync
    uv
    mise
    nodejs # includes npm
  ];
}
