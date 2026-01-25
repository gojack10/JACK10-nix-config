{ config, pkgs, fontSize, ... }:

{
  home.file.".config/wofi/style.css".text = ''
    window {
      background-color: #0f0f0f;
      color: #d0d0d0;
      font-family: "JetBrainsMono Nerd Font";
      font-size: ${toString (fontSize + 2)}px;
    }

    #input {
      background-color: #151515;
      color: #d0d0d0;
      border: none;
      padding: 8px;
    }

    #entry {
      padding: 8px;
    }

    #entry:selected {
      background-color: #6f6f6f;
      color: #ffffff;
    }
  '';
}
