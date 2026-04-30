{ config, pkgs, ... }:


{ pkgs, lib, ... }:

let
  # Symlink nerd fonts into ~/Library/Fonts so macOS apps can see them
  fontSymlinks = font: name: file:
    lib.nameValuePair
      "Library/Fonts/${builtins.baseNameOf file}"
      { source = "${font}/share/fonts/${name}/${builtins.baseNameOf file}"; };
in
{
  home.packages = with pkgs; [
    # Fonts (just the ones you actually use on macOS)
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
  ];

  # Symlink .ttf fonts into ~/Library/Fonts so they appear in all apps
  home.file = lib.mkMerge [
    (lib.listToAttrs (map (fontSymlinks pkgs.nerd-fonts.jetbrains-mono "JetBrainsMono")
      (builtins.filter (f: lib.hasSuffix ".ttf" f)
        (builtins.attrNames (builtins.readDir "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/JetBrainsMono")))))
    (lib.listToAttrs (map (fontSymlinks pkgs.nerd-fonts.symbols-only "NerdFonts")
      (builtins.filter (f: lib.hasSuffix ".ttf" f)
        (builtins.attrNames (builtins.readDir "${pkgs.nerd-fonts.symbols-only}/share/fonts/NerdFonts")))))
  ];
}

