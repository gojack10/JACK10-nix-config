{ config, pkgs, lib, hostname, ... }:

let
  home = config.home.homeDirectory;
  # Clients leave :8002 free for their SSH forward to this host.
  enabled = hostname == "m5-max";
  proxyScript = "${home}/.pi/agent/local-proxy.py";
  proxyLog = "${home}/.pi/agent/local-proxy.log";
  proxyVenv = "${home}/.local/share/local-llm-proxy-venv";
  proxyPython = "${proxyVenv}/bin/python";
in {
  home.packages = [ pkgs.uv ];

  home.file.".local/bin/local-ai" = lib.mkIf enabled {
    executable = true;
    text = ''
      #!/bin/sh
      exec ${lib.escapeShellArg home}/.pi/agent/local-ai "$@"
    '';
  };

  home.activation.setup-local-llm = lib.mkIf enabled (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${lib.escapeShellArg home}/.pi/agent ${lib.escapeShellArg home}/.mlx-lm
    if [ ! -x ${lib.escapeShellArg proxyPython} ]; then
      ${pkgs.uv}/bin/uv venv --python 3.14 ${lib.escapeShellArg proxyVenv}
    fi
    ${pkgs.uv}/bin/uv pip install --python ${lib.escapeShellArg proxyPython} aiohttp==3.14.3
  '');

  # Engines are proxy-owned and loaded only by a model request. MLX's reviewed
  # runtime is pinned in ~/.pi/agent/mlx-service/pin.json, not rebuilt by hms.
  launchd.agents.local-llm-proxy = lib.mkIf enabled {
    enable = true;
    config = {
      Label = "com.local.llm.proxy";
      ProgramArguments = [ proxyPython proxyScript ];
      WorkingDirectory = home;
      EnvironmentVariables = {
        HOME = home;
        PATH = "${home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
      };
      StandardOutPath = proxyLog;
      StandardErrorPath = proxyLog;
      ExitTimeOut = 60;
      RunAtLoad = true;
      KeepAlive = true;
    };
  };
}
