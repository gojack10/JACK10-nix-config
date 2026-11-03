{ config, pkgs, lib, hostname, ... }:

let
  dashboard = pkgs.callPackage ../../packages/m5-max-dashboard { };
  home = config.home.homeDirectory;
  logDir = "${home}/Library/Logs";
in lib.mkIf (hostname == "m5-max") {
  home.packages = [ dashboard ];

  # Retire the unmanaged Python/ASR service before the new loopback server starts.
  # Neither service configuration nor the surviving sources depend on ~/projects.
  home.activation.retire-legacy-m5-dashboard = lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ] ''
    legacy=${lib.escapeShellArg "${home}/Library/LaunchAgents/com.m5max.dashboard.plist"}
    if [ -e "$legacy" ]; then
      /bin/launchctl bootout --wait "gui/$(/usr/bin/id -u)/com.m5max.dashboard" 2>/dev/null || true
      rm -f "$legacy"
    fi
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
