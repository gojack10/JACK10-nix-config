{ config, pkgs, lib, hostname, ... }:

let
  dashboard = pkgs.callPackage ../../packages/m5-max-dashboard { };
  home = config.home.homeDirectory;
  logDir = "${home}/Library/Logs";
in lib.mkIf (hostname == "m5-max") {
  home.packages = [ dashboard ];

  home.activation.prepare-m5-max-dashboard = lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ] ''
    mkdir -p ${lib.escapeShellArg logDir}
  '';

  launchd.agents.m5-max-dashboard-web = {
    enable = true;
    config = {
      Label = "com.jack.m5-max-dashboard.web";
      ProgramArguments = [ "${dashboard}/bin/m5-max-dashboard-web" ];
      RunAtLoad = true;
      KeepAlive = { SuccessfulExit = false; };
      StandardOutPath = "${logDir}/m5-max-dashboard-web.log";
      StandardErrorPath = "${logDir}/m5-max-dashboard-web.err.log";
    };
  };

  # The bridge owns the signed helpers; the Swift sampler only reads loopback.
  launchd.agents.m5-max-dashboard-gpu = {
    enable = true;
    config = {
      Label = "com.jack.m5-max-dashboard.gpu";
      ProgramArguments = [ "${dashboard}/bin/m5-max-dashboard-gpu" ];
      RunAtLoad = true;
      KeepAlive = { SuccessfulExit = false; };
      ExitTimeOut = 40;
    };
  };

  launchd.agents.m5-max-dashboard-menu = {
    enable = true;
    config = {
      Label = "com.jack.m5-max-dashboard.menu";
      ProgramArguments = [ "${dashboard}/Applications/M5 Max Dashboard.app/Contents/MacOS/m5-max-dashboard-menu" ];
      LimitLoadToSessionType = "Aqua";
      RunAtLoad = true;
      # An intentional Quit stays quit until the next login or kickstart.
      KeepAlive = { SuccessfulExit = false; };
      StandardOutPath = "${logDir}/m5-max-dashboard-menu.log";
      StandardErrorPath = "${logDir}/m5-max-dashboard-menu.err.log";
    };
  };
}
