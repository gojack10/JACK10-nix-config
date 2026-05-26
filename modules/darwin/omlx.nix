{ config, pkgs, lib, ... }:

let
  home = config.home.homeDirectory;
  omlxDir = "${home}/omlx";
  omlxBin = "${omlxDir}/.venv/bin/omlx";
  modelDir = "${home}/.omlx/models";
  logFile = "${home}/.omlx/omlx.log";
  patchedBranch = "mtplx-sidecar-mtp-support";
  patchBaseRev = "9749c40";
  finalPatchSubject = "Enable MTP eligibility for VLM adapters";
  patchDir = ./omlx-patches;
in {
  # oMLX is currently a mutable git checkout installed with uv in ~/omlx.
  # Local commits from ~/omlx are captured in ./omlx-patches and applied on fresh machines.
  home.packages = with pkgs; [ uv git ];

  home.activation.setup-omlx = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${lib.escapeShellArg modelDir}

    if [ ! -d ${lib.escapeShellArg omlxDir}/.git ]; then
      ${pkgs.git}/bin/git clone https://github.com/jundot/omlx.git ${lib.escapeShellArg omlxDir}
    fi

    if [ -d ${lib.escapeShellArg omlxDir}/.git ]; then
      cd ${lib.escapeShellArg omlxDir}

      if [ -d .git/rebase-apply ]; then
        ${pkgs.git}/bin/git am --abort || true
      fi

      if ! ${pkgs.git}/bin/git rev-parse --verify --quiet ${lib.escapeShellArg patchedBranch} >/dev/null \
        || [ "$(${pkgs.git}/bin/git log -1 --format=%s ${lib.escapeShellArg patchedBranch} 2>/dev/null || true)" != ${lib.escapeShellArg finalPatchSubject} ]; then
        ${pkgs.git}/bin/git fetch origin main
        ${pkgs.git}/bin/git checkout -B ${lib.escapeShellArg patchedBranch} ${lib.escapeShellArg patchBaseRev}
        ${pkgs.git}/bin/git \
          -c user.name='Jack nix config' \
          -c user.email='jack@localhost' \
          am ${patchDir}/*.patch
      else
        ${pkgs.git}/bin/git checkout ${lib.escapeShellArg patchedBranch}
      fi
    fi

    if [ -f ${lib.escapeShellArg omlxDir}/pyproject.toml ] && [ ! -x ${lib.escapeShellArg omlxBin} ]; then
      cd ${lib.escapeShellArg omlxDir}
      ${pkgs.uv}/bin/uv venv --python 3.14
      ${pkgs.uv}/bin/uv pip install -e '.[audio,grammar]'
    fi
  '';

  launchd.agents.omlx-dflash = {
    enable = true;
    config = {
      Label = "com.omlx.dflash";
      ProgramArguments = [ "/bin/launchctl" "setenv" "DFLASH_MAX_CTX" "32768" ];
      RunAtLoad = true;
      LimitLoadToSessionType = "Aqua";
    };
  };

  launchd.agents.omlx-server = {
    enable = true;
    config = {
      Label = "com.omlx.server";
      ProgramArguments = [
        omlxBin
        "serve"
        "--model-dir"
        modelDir
      ];
      WorkingDirectory = home;
      EnvironmentVariables = {
        HOME = home;
        PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
        DFLASH_MAX_CTX = "32768";
      };
      StandardOutPath = logFile;
      StandardErrorPath = logFile;
      RunAtLoad = true;
      KeepAlive = true;
    };
  };
}
