{ config, lib, pkgs, ... }:

let
  fanPoke = pkgs.writeText "thinkpad-fan-min.py" ''
    import os
    import time

    with open("/sys/kernel/debug/ec/ec0/io", "r+b", buffering=0) as ec:
        while True:
            ec.seek(0x2F)
            ec.write(bytes([0x08]))
            time.sleep(0.02)
  '';

  fanMode = pkgs.writeShellApplication {
    name = "fan-mode";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      case "''${1:-}" in
        full)
          systemctl stop thinkpad-fan-min.service || true
          echo "level disengaged" > /proc/acpi/ibm/fan
          ;;
        normal)
          echo "level auto" > /proc/acpi/ibm/fan
          systemctl start thinkpad-fan-min.service
          ;;
        status)
          if systemctl is-active --quiet thinkpad-fan-min.service; then
            echo "run: thinkpad-fan-min"
          else
            echo "down: thinkpad-fan-min"
          fi
          ;;
        *)
          echo "usage: fan-mode {full|normal|status}" >&2
          exit 2
          ;;
      esac
    '';
  };

  zzz = pkgs.writeShellScriptBin "zzz" ''
    exec ${pkgs.systemd}/bin/systemctl suspend
  '';

  reverseTunnel = pkgs.writeShellScript "reverse-tunnel-10server" ''
    set -eu

    config_file=/home/jack/.config/JACK10-nix-config/local/ssh.env
    if [ ! -f "$config_file" ]; then
      echo "missing $config_file" >&2
      exit 78
    fi

    # shellcheck disable=SC1090
    . "$config_file"
    target="''${JACK10_REVERSE_SSH_TUNNEL_TARGET:-''${JACK10_SSH_TARGET:-}}"
    port="''${JACK10_REVERSE_SSH_TUNNEL_PORT:-''${JACK10_SSH_PORT:-}}"
    forwards="''${JACK10_REVERSE_SSH_TUNNEL_REMOTE_FORWARDS:-}"
    [ -n "$target" ] && [ -n "$forwards" ] || exit 78

    set -- ${pkgs.autossh}/bin/autossh -M 0 -N -T \
      -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=30 \
      -o ServerAliveCountMax=3 \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=10
    [ -z "$port" ] || set -- "$@" -p "$port"
    for forward in $forwards; do
      set -- "$@" -R "$forward"
    done
    exec "$@" "$target"
  '';
in {
  imports = [ ./hardware-configuration.nix ];

  networking = {
    hostName = "10top";
    firewall.enable = true;
    wireless.iwd = {
      enable = true;
      settings = {
        General.EnableNetworkConfiguration = true;
        Network.NameResolvingService = "resolvconf";
      };
    };
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    consoleLogLevel = 1;
    kernelParams = [ "i915.fastboot=1" ];
    extraModprobeConfig = ''
      options thinkpad_acpi fan_control=1
      options ec_sys write_support=1
      options psmouse synaptics_intertouch=1
    '';
  };

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  virtualisation.docker.enable = true;

  hardware = {
    enableRedistributableFirmware = true;
    firmware = [ pkgs.linux-firmware ];
    bluetooth.enable = true;
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = [ pkgs.intel-media-driver ];
    };
  };

  services = {
    openssh.enable = true;
    seatd.enable = true;
    tlp.enable = true;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
    logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
    };
    cloudflared = {
      enable = true;
      tunnels."c4c8f0cc-c904-43f4-b1bd-823b198e0d76" = {
        credentialsFile = "/var/lib/cloudflared/c4c8f0cc-c904-43f4-b1bd-823b198e0d76.json";
        ingress = {
          "10top-app-origin.sifttext.com" = "http://127.0.0.1:8000";
          "10top-auth-origin.sifttext.com" = "http://127.0.0.1:8085";
        };
        default = "http_status:404";
      };
    };
    greetd = {
      enable = true;
      useTextGreeter = true;
      settings.default_session = {
        user = "greeter";
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${pkgs.sway}/bin/sway";
      };
    };
  };

  # LiDM was the old TTY display manager. It cannot run alongside the owner's
  # selected greetd login, so greetd replaces (rather than duplicates) it.

  programs = {
    sway.enable = true;
    zsh.enable = true;
  };

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  security = {
    polkit.enable = true;
    rtkit.enable = true;
    wrappers.intel_gpu_top = {
      source = "${pkgs.intel-gpu-tools}/bin/intel_gpu_top";
      capabilities = "cap_perfmon+ep";
      owner = "root";
      group = "root";
    };
    sudo.extraRules = [
      {
        users = [ "jack" ];
        commands = [
          { command = "ALL"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/fan-mode full"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/fan-mode normal"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/fan-mode status"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/zzz"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/poweroff"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/reboot"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];
  };

  users = {
    groups = {
      jack.gid = 1000;
      adbusers = { };
      networkmanager = { };
      optical = { };
      scanner = { };
      sgx = { };
      usbmon = { };
    };
    users.jack = {
      isNormalUser = true;
      uid = 1000;
      group = "jack";
      home = "/home/jack";
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDBJDWUtn/tqOhWEK10VO4WbgCqZeSbomwB6l7+2GOWj gojack10@gmail.com_m5_max" ];
      extraGroups = [
        "wheel" "audio" "video" "kvm" "input" "cdrom" "optical"
        "dialout" "scanner" "lp" "tty" "disk" "sgx" "usbmon"
        "networkmanager" "seat" "adbusers" "docker"
      ];
      subUidRanges = [{ startUid = 100000; count = 65536; }];
      subGidRanges = [{ startGid = 100000; count = 65536; }];
    };
  };

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/backlight/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/backlight/%k/brightness"
  '';

  systemd.services = {
    thinkpad-fan-min = {
      description = "Keep the ThinkPad EC fan near its minimum active speed";
      wantedBy = [ "multi-user.target" ];
      after = [ "sys-kernel-debug.mount" ];
      requires = [ "sys-kernel-debug.mount" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${fanPoke}";
        Restart = "always";
        RestartSec = 1;
      };
    };

    reverse-tunnel-10server = {
      description = "Reverse SSH tunnel to 10SERVER";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = "jack";
        WorkingDirectory = "/home/jack";
        ExecStart = reverseTunnel;
        Environment = "AUTOSSH_GATETIME=0";
        Restart = "always";
        RestartSec = 60;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    fanMode
    zzz
    autossh
    chromium
    intel-gpu-tools
  ];

  system.stateVersion = "25.11";
}
