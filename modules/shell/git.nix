{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    settings.user.name = "jack";
    settings.user.email = "gojack10@gmail.com";
    settings.init.defaultBranch = "main";
    settings.credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
  };
}
