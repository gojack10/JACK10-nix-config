{ config, pkgs, lib, settings, ... }:

let
  personalIdentity = settings.gitName != null && settings.gitEmail != null;
in {
  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
      credential = {
        helper = "";
        "https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
      };
    } // lib.optionalAttrs personalIdentity {
      user.name = settings.gitName;
      user.email = settings.gitEmail;
    };
  };
}
