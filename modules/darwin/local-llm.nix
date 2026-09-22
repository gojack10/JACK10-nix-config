{ config, pkgs, lib, ... }:

let
  home = config.home.homeDirectory;
  mlxSource = "${home}/mlx-lm-src";
  mlxServer = "${home}/.local/bin/mlx_lm.server";
  mlxHome = "${home}/.mlx-lm";
  mlxLog = "${mlxHome}/mlx-lm.log";
  proxyScript = "${home}/.pi/agent/local-proxy.py";
  proxyLog = "${home}/.pi/agent/local-proxy.log";
  proxyVenv = "${home}/.local/share/local-llm-proxy-venv";
  proxyPython = "${proxyVenv}/bin/python";
in {
  home.packages = with pkgs; [ uv git ];

  # mlx-lm serves one checkpoint per process. local-proxy.py atomically writes
  # the desired checkpoint path and owns every bootout/bootstrap transition.
  home.file.".mlx-lm/mlx-server.sh" = {
    force = true;
    executable = true;
    text = ''
      #!/bin/sh
      set -eu

      DESIRED="''${HOME}/.mlx-lm/desired-model"
      [ -r "$DESIRED" ] || { echo "mlx-lm: no desired-model file; refusing to start" >&2; exit 1; }

      MODEL=$(${pkgs.coreutils}/bin/tr -d ' \t\n' < "$DESIRED")
      [ -n "$MODEL" ] || { echo "mlx-lm: desired-model is empty" >&2; exit 1; }
      [ -d "$MODEL" ] || { echo "mlx-lm: desired checkpoint does not exist: $MODEL" >&2; exit 1; }

      exec ${lib.escapeShellArg mlxServer} --model "$MODEL" --host 127.0.0.1 --port 8000
    '';
  };

  home.activation.setup-local-llm = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${lib.escapeShellArg mlxHome} ${lib.escapeShellArg home}/.pi/agent

    if [ ! -d ${lib.escapeShellArg mlxSource}/.git ]; then
      ${pkgs.git}/bin/git clone https://github.com/ml-explore/mlx-lm.git ${lib.escapeShellArg mlxSource}
    fi

    if [ -d ${lib.escapeShellArg mlxSource}/.git ]; then
      ${pkgs.git}/bin/git -C ${lib.escapeShellArg mlxSource} fetch origin main
      ${pkgs.git}/bin/git -C ${lib.escapeShellArg mlxSource} checkout -B main origin/main
      HOME=${lib.escapeShellArg home} ${pkgs.uv}/bin/uv tool install --force --from ${lib.escapeShellArg mlxSource} mlx-lm
    fi

    if [ ! -x ${lib.escapeShellArg proxyPython} ]; then
      ${pkgs.uv}/bin/uv venv --python 3.14 ${lib.escapeShellArg proxyVenv}
    fi
    ${pkgs.uv}/bin/uv pip install --python ${lib.escapeShellArg proxyPython} aiohttp==3.14.3
  '';

  launchd.agents.mlx-lm-server = {
    enable = true;
    config = {
      Label = "com.mlx-lm.server";
      ProgramArguments = [ "/bin/sh" "-c" "exec ${mlxHome}/mlx-server.sh" ];
      WorkingDirectory = home;
      EnvironmentVariables = {
        HOME = home;
        PATH = "${home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
      };
      StandardOutPath = mlxLog;
      StandardErrorPath = mlxLog;
      ExitTimeOut = 60;
      RunAtLoad = true;
      KeepAlive = false;
    };
  };

  launchd.agents.local-llm-proxy = {
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
      RunAtLoad = true;
      KeepAlive = true;
    };
  };
}
