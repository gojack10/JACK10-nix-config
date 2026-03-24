#!/bin/bash
# VT Capture for OBS
# Captures the VT framebuffer via v4l2loopback and auto-switches OBS scenes
# when toggling between Sway and a VT.
#
# PREREQUISITES:
#   - Kernel module: v4l2loopback
#   - Packages: ffmpeg
#   - OBS Lua script: obs-vt-scene-switcher.lua (add via Tools > Scripts)
#
# SETUP IN OBS:
#   1. Create two scenes: "Sway" and "VT"
#   2. "Sway" scene: PipeWire screen capture + webcam overlay
#   3. "VT" scene: V4L2 Video Capture (select "VT Capture" device) + webcam overlay
#   4. Tools > Scripts > + > select obs-vt-scene-switcher.lua
#
# USAGE:
#   sudo vt-capture start     # Load module + start fbdev capture
#   sudo vt-capture stop      # Stop capture + unload module
#   vt-capture watch           # Run VT switch watcher (no sudo needed)
#   sudo vt-capture setup      # First-time: load module + start capture + launch watcher

set -euo pipefail

V4L2_DEVICE="/dev/video10"
V4L2_LABEL="VT Capture"
RESOLUTION="1920x1080"
FRAMERATE=30
PIDFILE="/tmp/vt-capture-ffmpeg.pid"
WATCHPIDFILE="/tmp/vt-capture-watch.pid"
SCENE_FILE="/tmp/vt-capture-scene"

OBS_SCENE_SWAY="Sway"
OBS_SCENE_VT="VT"

# Which VT to watch for (the one you work in)
TARGET_VT="tty2"

usage() {
    echo "Usage: vt-capture {start|stop|watch|setup|status}"
    echo ""
    echo "  start   - Load v4l2loopback and start framebuffer capture (requires sudo)"
    echo "  stop    - Stop capture and unload module (requires sudo)"
    echo "  watch   - Monitor active VT and switch OBS scenes via file"
    echo "  setup   - Full setup: start + watch"
    echo "  status  - Show current state"
    exit 1
}

cmd_start() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: 'start' requires sudo"
        exit 1
    fi

    # Load v4l2loopback if not loaded
    if ! lsmod | grep -q v4l2loopback; then
        echo "Loading v4l2loopback module..."
        modprobe v4l2loopback \
            devices=1 \
            video_nr=10 \
            card_label="$V4L2_LABEL" \
            exclusive_caps=1
    else
        echo "v4l2loopback already loaded."
    fi

    # Check device exists
    if [[ ! -e "$V4L2_DEVICE" ]]; then
        echo "Error: $V4L2_DEVICE not found after loading module"
        exit 1
    fi

    # Stop existing ffmpeg if running
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Stopping existing capture..."
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        sleep 1
    fi

    echo "Starting KMS capture: kmsgrab -> $V4L2_DEVICE"
    ffmpeg \
        -f kmsgrab \
        -framerate "$FRAMERATE" \
        -i - \
        -vf 'hwmap=derive_device=vaapi,hwdownload,format=bgr0,format=yuv420p' \
        -f v4l2 \
        "$V4L2_DEVICE" \
        </dev/null >/dev/null 2>&1 &

    echo $! > "$PIDFILE"
    echo "Capture started (PID: $(cat "$PIDFILE"))"
}

cmd_stop() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: 'stop' requires sudo"
        exit 1
    fi

    # Stop watcher
    if [[ -f "$WATCHPIDFILE" ]] && kill -0 "$(cat "$WATCHPIDFILE")" 2>/dev/null; then
        echo "Stopping VT watcher..."
        kill "$(cat "$WATCHPIDFILE")" 2>/dev/null || true
        rm -f "$WATCHPIDFILE"
    fi

    # Stop ffmpeg
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Stopping capture..."
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
    else
        echo "No capture running."
    fi

    # Clean up scene file
    rm -f "$SCENE_FILE"

    # Unload module
    if lsmod | grep -q v4l2loopback; then
        echo "Unloading v4l2loopback..."
        sleep 1
        modprobe -r v4l2loopback
    fi

    echo "Stopped."
}

cmd_watch() {
    echo "Watching VT switches (target: $TARGET_VT)..."
    echo "OBS scenes: '$OBS_SCENE_SWAY' (desktop) / '$OBS_SCENE_VT' (terminal)"
    echo "Scene file: $SCENE_FILE"
    echo "Press Ctrl+C to stop."

    # Save PID for cleanup
    echo $$ > "$WATCHPIDFILE"
    trap 'rm -f "$WATCHPIDFILE" "$SCENE_FILE"; exit 0' INT TERM

    local last_state=""

    while true; do
        current_vt=$(cat /sys/class/tty/tty0/active 2>/dev/null || echo "unknown")

        if [[ "$current_vt" == "$TARGET_VT" && "$last_state" != "vt" ]]; then
            echo "[$(date +%H:%M:%S)] Switched to $TARGET_VT -> OBS scene: $OBS_SCENE_VT"
            echo "$OBS_SCENE_VT" > "$SCENE_FILE"
            last_state="vt"
        elif [[ "$current_vt" != "$TARGET_VT" && "$last_state" != "sway" ]]; then
            echo "[$(date +%H:%M:%S)] Switched to $current_vt -> OBS scene: $OBS_SCENE_SWAY"
            echo "$OBS_SCENE_SWAY" > "$SCENE_FILE"
            last_state="sway"
        fi

        sleep 0.5
    done
}

cmd_status() {
    echo "=== VT Capture Status ==="

    # Module
    if lsmod | grep -q v4l2loopback; then
        echo "v4l2loopback: loaded"
    else
        echo "v4l2loopback: not loaded"
    fi

    # Device
    if [[ -e "$V4L2_DEVICE" ]]; then
        echo "Device: $V4L2_DEVICE exists"
    else
        echo "Device: $V4L2_DEVICE missing"
    fi

    # FFmpeg capture
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "Capture: running (PID: $(cat "$PIDFILE"))"
    else
        echo "Capture: not running"
    fi

    # Watcher
    if [[ -f "$WATCHPIDFILE" ]] && kill -0 "$(cat "$WATCHPIDFILE")" 2>/dev/null; then
        echo "Watcher: running (PID: $(cat "$WATCHPIDFILE"))"
    else
        echo "Watcher: not running"
    fi

    # Scene file
    if [[ -f "$SCENE_FILE" ]]; then
        echo "Current scene: $(cat "$SCENE_FILE")"
    else
        echo "Scene file: not created yet"
    fi

    # Active VT
    echo "Active VT: $(cat /sys/class/tty/tty0/active 2>/dev/null || echo 'unknown')"
}

cmd_setup() {
    cmd_start
    echo ""
    echo "Now run without sudo in another terminal:"
    echo "  vt-capture watch"
    echo ""
    echo "Make sure the OBS Lua script is loaded:"
    echo "  Tools > Scripts > + > obs-vt-scene-switcher.lua"
}

case "${1:-}" in
    start) cmd_start ;;
    stop)  cmd_stop ;;
    watch) cmd_watch ;;
    setup) cmd_setup ;;
    status) cmd_status ;;
    *) usage ;;
esac
