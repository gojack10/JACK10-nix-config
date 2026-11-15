{ ... }:

{
  home.file.".config/nvim/lua/music/init.lua".source = ./files/music.lua;

  # Nix owns both source files. The tree menu consumes the same shared.lua
  # through modules/scripts.nix, without loading this regular-editor profile.
  home.file.".config/nvim/init.lua".text = ''
    dofile("${./files/shared.lua}")
    dofile("${./files/nix-specific.lua}")
  '';
}
