{ config, pkgs, ... }:

let
  audioCatchall = pkgs.writeShellScriptBin "audio-catchall" ''
    set -euo pipefail

    ffmpeg="${pkgs.ffmpeg}/bin/ffmpeg"
    switch_audio="${pkgs.switchaudio-osx}/bin/SwitchAudioSource"
    driver_src="${pkgs.blackhole}/Library/Audio/Plug-Ins/HAL/Blackhole256ch.driver"
    driver_dst="/Library/Audio/Plug-Ins/HAL/Blackhole256ch.driver"

    usage() {
      cat <<'EOF'
    usage: audio-catchall <command> [args]

    Commands:
      setup              Install/check BlackHole and print routing notes
      install-driver     Idempotently install BlackHole HAL driver into /Library
      devices            List ffmpeg/CoreAudio capture/playback devices
      record [file]      Manual mode: record mic + BlackHole until Ctrl-C
      auto [file]        Easy mode: set output to BlackHole, monitor to AirPods
                         if connected, else MacBook speakers, and record
      auto-mac [file]    Easy mode, but prefer MacBook speakers for monitoring

    Environment:
      AUDIO_CATCHALL_MIC=<regex>      Override microphone choice
      AUDIO_CATCHALL_MONITOR=<regex>  Override monitor output choice

    Easy mode is the closest free "just works" path: apps send audio to
    BlackHole, ffmpeg records it, and ffmpeg simultaneously plays it to your
    AirPods/speakers. On exit, your previous macOS output is restored.

    Zoom caveat: Zoom Speaker must be "Same as System"/default. If Zoom is
    hard-coded to AirPods, it bypasses BlackHole and cannot be captured here.
    EOF
    }

    installed_driver() {
      find /Library/Audio/Plug-Ins/HAL -maxdepth 1 \( -iname 'BlackHole*.driver' -o -iname 'Blackhole*.driver' \) -print 2>/dev/null | head -n 1
    }

    install_driver() {
      existing="$(installed_driver || true)"
      if [ -n "$existing" ]; then
        echo "BlackHole already installed: $existing"
        return 0
      fi

      echo "Installing BlackHole driver to $driver_dst"
      echo "This needs sudo because CoreAudio HAL drivers live under /Library."
      sudo mkdir -p /Library/Audio/Plug-Ins/HAL
      sudo cp -R "$driver_src" "$driver_dst"
      echo "Restarting CoreAudio so BlackHole appears as an audio device."
      sudo killall -9 coreaudiod 2>/dev/null || true
    }

    list_devices() {
      echo "== Current output =="
      "$switch_audio" -t output -c 2>/dev/null || true
      echo
      echo "== Current system output =="
      "$switch_audio" -t system -c 2>/dev/null || true
      echo
      echo "== Current input =="
      "$switch_audio" -t input -c 2>/dev/null || true
      echo
      echo "== All outputs =="
      "$switch_audio" -t output -a 2>/dev/null || true
      echo
      echo "== All inputs =="
      "$switch_audio" -t input -a 2>/dev/null || true
      echo
      echo "== ffmpeg avfoundation capture devices =="
      "$ffmpeg" -hide_banner -f avfoundation -list_devices true -i "" 2>&1 || true
      echo
      echo "== ffmpeg AudioToolbox playback devices =="
      "$ffmpeg" -hide_banner -f lavfi -i anullsrc=r=48000:cl=stereo -t 0.01 -f audiotoolbox -list_devices true - 2>&1 || true
    }

    av_audio_index_regex() {
      re="$1"
      "$ffmpeg" -hide_banner -f avfoundation -list_devices true -i "" 2>&1 |
        awk -v re="$re" '
          /AVFoundation audio devices:/ { audio=1; next }
          audio && /\[[0-9]+\]/ {
            idx=$0; sub(/^.*\[/, "", idx); sub(/\].*$/, "", idx)
            name=$0; sub(/^.*\] /, "", name)
            if (tolower(name) ~ tolower(re)) { print idx; exit }
          }
        '
    }

    av_audio_index_exact() {
      want="$1"
      "$ffmpeg" -hide_banner -f avfoundation -list_devices true -i "" 2>&1 |
        awk -v want="$want" '
          /AVFoundation audio devices:/ { audio=1; next }
          audio && /\[[0-9]+\]/ {
            idx=$0; sub(/^.*\[/, "", idx); sub(/\].*$/, "", idx)
            name=$0; sub(/^.*\] /, "", name)
            if (tolower(name) == tolower(want)) { print idx; exit }
          }
        '
    }

    av_audio_name_by_index() {
      want="$1"
      "$ffmpeg" -hide_banner -f avfoundation -list_devices true -i "" 2>&1 |
        awk -v want="$want" '
          /AVFoundation audio devices:/ { audio=1; next }
          audio && /\[[0-9]+\]/ {
            idx=$0; sub(/^.*\[/, "", idx); sub(/\].*$/, "", idx)
            name=$0; sub(/^.*\] /, "", name)
            if (idx == want) { print name; exit }
          }
        '
    }

    at_output_match_regex() {
      re="$1"
      "$ffmpeg" -hide_banner -f lavfi -i anullsrc=r=48000:cl=stereo -t 0.01 -f audiotoolbox -list_devices true - 2>&1 |
        awk -v re="$re" '
          /CoreAudio devices:/ { audio=1; next }
          audio && /\[[0-9]+\]/ {
            # Duplex (Bluetooth) devices are listed twice, suffixed :input and
            # :output. We are choosing a *playback* sink, so skip the capture
            # side; otherwise the first match (e.g. AirPods :input) wins and
            # AudioQueueStart fails because you cannot play into an input.
            if ($0 ~ /:input *$/) next
            idx=$0; sub(/^.*\[/, "", idx); sub(/\].*$/, "", idx)
            name=$0; sub(/^.*\] */, "", name); sub(/, .*$/, "", name); gsub(/^ +| +$/, "", name)
            lname=tolower(name)
            if (lname !~ /blackhole/ && lname !~ /microphone/ && tolower(name) ~ tolower(re)) {
              print idx "\t" name
              exit
            }
          }
        '
    }

    choose_blackhole_name() {
      "$switch_audio" -t output -a 2>/dev/null | awk 'tolower($0) ~ /blackhole/ { print; exit }'
    }

    choose_mic_index() {
      mic_idx=""
      if [ -n "''${AUDIO_CATCHALL_MIC:-}" ]; then
        mic_idx="$(av_audio_index_regex "$AUDIO_CATCHALL_MIC" || true)"
      fi
      if [ -z "$mic_idx" ]; then
        # Prefer built-in mic. AirPods mics force Bluetooth headset mode and
        # commonly produce crackly/low-bandwidth recordings.
        mic_idx="$(av_audio_index_regex 'macbook.*microphone|built.?in.*microphone' || true)"
      fi
      if [ -z "$mic_idx" ]; then
        mic_name="$("$switch_audio" -t input -c 2>/dev/null || true)"
        if [ -n "$mic_name" ]; then
          mic_idx="$(av_audio_index_exact "$mic_name" || true)"
        fi
      fi
      if [ -z "$mic_idx" ]; then
        mic_idx="$(av_audio_index_regex 'microphone|airpods' || true)"
      fi
      printf '%s\n' "$mic_idx"
    }

    choose_monitor_output() {
      mode="''${1:-airpods}"
      if [ -n "''${AUDIO_CATCHALL_MONITOR:-}" ]; then
        at_output_match_regex "$AUDIO_CATCHALL_MONITOR"
        return
      fi

      if [ "$mode" = "mac" ]; then
        at_output_match_regex 'macbook.*speakers|built.?in.*speaker|speakers' && return
        at_output_match_regex 'airpods' && return
      else
        at_output_match_regex 'airpods' && return
        at_output_match_regex 'macbook.*speakers|built.?in.*speaker|speakers' && return
      fi

      at_output_match_regex '.*'
    }

    record_manual() {
      out="''${1:-$HOME/Desktop/audio-$(date +%Y%m%d-%H%M%S).m4a}"

      blackhole_idx="$(av_audio_index_regex 'blackhole' || true)"
      if [ -z "$blackhole_idx" ]; then
        echo "error: BlackHole is not visible to ffmpeg/CoreAudio." >&2
        echo "run: audio-catchall setup" >&2
        exit 1
      fi

      mic_idx="$(choose_mic_index)"
      if [ -z "$mic_idx" ]; then
        echo "error: could not find a microphone input." >&2
        list_devices >&2
        exit 1
      fi
      mic_name="$(av_audio_name_by_index "$mic_idx" || true)"
      case "$(printf '%s' "$mic_name" | tr '[:upper:]' '[:lower:]')" in
        *airpods*)
          echo "warning: using AirPods as the microphone can sound crackly because macOS switches Bluetooth into headset mode." >&2
          ;;
      esac

      current_output="$("$switch_audio" -t output -c 2>/dev/null || true)"
      case "$(printf '%s' "$current_output" | tr '[:upper:]' '[:lower:]')" in
        *multi-output*|*catch-all*|*aggregate*) ;;
        *blackhole*)
          echo "warning: current output is '$current_output', so you are sending audio only to the recorder." >&2
          echo "you will not hear Mac audio unless output is a Multi-Output Device with BlackHole + speakers/AirPods." >&2
          ;;
        *)
          echo "warning: current output is '$current_output'." >&2
          echo "system/app audio is captured only if output routes through a Multi-Output Device containing BlackHole." >&2
          ;;
      esac

      echo "Recording mic '$mic_name' index :$mic_idx + BlackHole/system index :$blackhole_idx"
      echo "Output: $out"
      echo "Press Ctrl-C to stop."
      exec "$ffmpeg" -hide_banner -y \
        -thread_queue_size 1024 -f avfoundation -i ":$mic_idx" \
        -thread_queue_size 1024 -f avfoundation -i ":$blackhole_idx" \
        -filter_complex "[0:a]aresample=48000:async=1:first_pts=0,pan=stereo|c0=c0|c1=c0[mic];[1:a]aresample=48000:async=1:first_pts=0,pan=stereo|c0=c0|c1=c1[sys];[mic][sys]amix=inputs=2:duration=longest:dropout_transition=0:normalize=1,alimiter=limit=0.95[a]" \
        -map "[a]" -ar 48000 -c:a aac -b:a 192k "$out"
    }

    record_auto() {
      mode="''${1:-airpods}"
      shift || true
      out="''${1:-$HOME/Desktop/audio-$(date +%Y%m%d-%H%M%S).m4a}"

      if [ -z "$(choose_blackhole_name || true)" ] || [ -z "$(av_audio_index_regex 'blackhole' || true)" ]; then
        install_driver
        sleep 2
      fi

      blackhole_name="$(choose_blackhole_name || true)"
      blackhole_idx="$(av_audio_index_regex 'blackhole' || true)"
      mic_idx="$(choose_mic_index)"
      monitor_match="$(choose_monitor_output "$mode" || true)"

      if [ -z "$blackhole_name" ] || [ -z "$blackhole_idx" ]; then
        echo "error: BlackHole is not visible." >&2
        echo "run: audio-catchall setup" >&2
        exit 1
      fi
      if [ -z "$mic_idx" ]; then
        echo "error: could not find a microphone input." >&2
        list_devices >&2
        exit 1
      fi
      if [ -z "$monitor_match" ]; then
        echo "error: could not find a monitor output device." >&2
        list_devices >&2
        exit 1
      fi

      monitor_idx="$(printf '%s' "$monitor_match" | awk -F '\t' '{ print $1 }')"
      monitor_name="$(printf '%s' "$monitor_match" | awk -F '\t' '{ print $2 }')"
      mic_name="$(av_audio_name_by_index "$mic_idx" || true)"
      old_output="$("$switch_audio" -t output -c 2>/dev/null || true)"
      old_system="$("$switch_audio" -t system -c 2>/dev/null || true)"

      restore_audio() {
        if [ -n "''${old_output:-}" ]; then
          "$switch_audio" -t output -s "$old_output" >/dev/null 2>&1 || true
        fi
        if [ -n "''${old_system:-}" ]; then
          "$switch_audio" -t system -s "$old_system" >/dev/null 2>&1 || true
        fi
      }
      trap restore_audio EXIT INT TERM

      echo "Setting macOS output to '$blackhole_name' for capture."
      "$switch_audio" -t output -s "$blackhole_name" >/dev/null
      "$switch_audio" -t system -s "$blackhole_name" >/dev/null 2>&1 || true

      echo "Monitoring captured system audio to '$monitor_name' (AudioToolbox index $monitor_idx)."
      echo "Recording mic '$mic_name' + system audio to: $out"
      echo "Press Ctrl-C to stop; previous output '$old_output' will be restored."
      echo "For Zoom, set Speaker to 'Same as System' if it is not already."

      ffmpeg_pid=""
      cleanup() {
        trap - EXIT INT TERM
        if [ -n "$ffmpeg_pid" ] && kill -0 "$ffmpeg_pid" >/dev/null 2>&1; then
          # ffmpeg can be slow to honor SIGINT while AudioToolbox is open. Give
          # it a few seconds to finalize the m4a, then escalate so audio output
          # restoration never gets stuck behind a wedged playback sink.
          kill -INT "$ffmpeg_pid" >/dev/null 2>&1 || true
          for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$ffmpeg_pid" >/dev/null 2>&1 || break
            sleep 0.5
          done
          if kill -0 "$ffmpeg_pid" >/dev/null 2>&1; then
            kill -TERM "$ffmpeg_pid" >/dev/null 2>&1 || true
            sleep 1
          fi
          if kill -0 "$ffmpeg_pid" >/dev/null 2>&1; then
            kill -KILL "$ffmpeg_pid" >/dev/null 2>&1 || true
          fi
          wait "$ffmpeg_pid" >/dev/null 2>&1 || true
        fi
        restore_audio
      }
      trap cleanup EXIT
      trap 'cleanup; exit 130' INT TERM

      "$ffmpeg" -hide_banner -y \
        -thread_queue_size 1024 -f avfoundation -i ":$mic_idx" \
        -thread_queue_size 1024 -f avfoundation -i ":$blackhole_idx" \
        -filter_complex "[0:a]aresample=48000:async=1:first_pts=0,pan=stereo|c0=c0|c1=c0[mic];[1:a]aresample=48000:async=1:first_pts=0,pan=stereo|c0=c0|c1=c1,asplit=2[sys_rec][sys_mon];[mic][sys_rec]amix=inputs=2:duration=longest:dropout_transition=0:normalize=1,alimiter=limit=0.95[rec]" \
        -map "[rec]" -ar 48000 -c:a aac -b:a 192k \
        -movflags +empty_moov+default_base_moof -frag_duration 1000000 "$out" \
        -map "[sys_mon]" -ar 48000 -c:a pcm_s16le -audio_device_index "$monitor_idx" -f audiotoolbox - &
      ffmpeg_pid="$!"
      set +e
      wait "$ffmpeg_pid"
      status="$?"
      set -e
      ffmpeg_pid=""
      trap - EXIT INT TERM
      restore_audio
      exit "$status"
    }

    setup() {
      install_driver
      cat <<'EOF'

    Easiest usage:

      audio-catchall auto

    That command sets system output to BlackHole, records BlackHole + your mic,
    plays the captured system audio back to AirPods if connected otherwise
    MacBook speakers, and restores your previous output when it exits.

    Manual/Multi-Output usage is still possible:

    1. Open Audio MIDI Setup.
    2. Press + -> Create Multi-Output Device.
    3. Check BlackHole (2ch or 256ch) and the output you want to hear.
    4. Enable Drift Correction on the non-master device if shown.
    5. Right-click the Multi-Output Device -> Use This Device For Sound Output.
    6. Run: audio-catchall record
    EOF
      open -a "Audio MIDI Setup" 2>/dev/null || true
    }

    cmd="''${1:-help}"
    shift || true
    case "$cmd" in
      setup) setup "$@" ;;
      install-driver) install_driver "$@" ;;
      devices) list_devices "$@" ;;
      record) record_manual "$@" ;;
      auto) record_auto airpods "$@" ;;
      auto-mac) record_auto mac "$@" ;;
      help|-h|--help) usage ;;
      *) usage >&2; exit 2 ;;
    esac
  '';

  recordCatchall = pkgs.writeShellScriptBin "record-catchall" ''
    exec ${audioCatchall}/bin/audio-catchall auto "$@"
  '';

  recordMic = pkgs.stdenv.mkDerivation {
    pname = "record-mic";
    version = "1";
    src = ../../scripts/record-mic.c;
    dontUnpack = true;
    buildPhase = ''
      $CC -O2 -Wall -Wextra -DFFMPEG_PATH='"${pkgs.ffmpeg}/bin/ffmpeg"' "$src" -o record-mic
    '';
    installPhase = ''
      install -Dm755 record-mic "$out/bin/record-mic"
    '';
  };
in
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "unrar"
  ];

  home.packages = with pkgs; [
    # Fonts (nerd fonts install to nix profile; macOS apps can find them)
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    ghostty-bin

    # Catch-all audio recording support. ffmpeg records, BlackHole provides the
    # CoreAudio loopback driver, and switchaudio-osx lets helper scripts inspect
    # current input/output devices without --impure.
    ffmpeg
    blackhole
    switchaudio-osx
    audioCatchall
    recordCatchall
    recordMic

    rustup
    docker
    colima

    # Fast RAR extraction (official rarlab decoder, solid-archive safe)
    unrar
  ];
}
