{ config, pkgs, lib, hostname, ... }:

let
  home = config.home.homeDirectory;
  enabled = hostname == "m5-max";
  logDir = "${home}/.gpu-usage";
  script = "${home}/.local/bin/gpu-over-50";
in {
  home.file.".local/bin/gpu-over-50" = lib.mkIf enabled {
    source = ../../scripts/gpu-over-50;
    executable = true;
    force = true;
  };

  home.activation.setup-gpu-over-50 = lib.mkIf enabled (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${lib.escapeShellArg logDir}
  '');

  launchd.agents.gpu-over-50 = lib.mkIf enabled {
    enable = true;
    config = {
      Label = "com.jack.gpu-over-50";
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        script
        "--threshold"
        "50"
        "--output"
        "${logDir}/gpu-episodes.jsonl"
      ];
      WorkingDirectory = home;
      EnvironmentVariables = {
        HOME = home;
        PATH = "/usr/bin:/bin";
      };
      StandardOutPath = "${logDir}/launchd.out.log";
      StandardErrorPath = "${logDir}/launchd.err.log";
      RunAtLoad = true;
      KeepAlive = {
        SuccessfulExit = false;
      };
      ThrottleInterval = 300;
    };
  };
}
