{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    settings.user.name = "jack";
    settings.user.email = "gojack10@gmail.com";  
  };
}
