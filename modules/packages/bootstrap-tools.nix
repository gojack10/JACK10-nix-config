{ pkgs, lib, config, ... }:

let
  nodejs = pkgs.nodejs_24 or pkgs.nodejs;
in {
  home.packages = with pkgs; [
    git
    gh
    rsync
    uv
    mise
    nodejs # includes npm
  ];

  home.activation.install-uv-tools = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.uv}/bin/uv tool install yt-dlp --force
    ${pkgs.uv}/bin/uv tool install duckdb-cli --force
    ${pkgs.uv}/bin/uv tool install huggingface-hub --force
  '';
}
