#!/usr/bin/env bash
set -euo pipefail

DEFAULT_USER="$(whoami)"
DEFAULT_PORT="22"
DEFAULT_PROJECT="~/projects/deepwork"
LOCAL_BIN="$HOME/.local/bin"

read -rp "Build SSH user [$DEFAULT_USER]: " USER
USER="${USER:-$DEFAULT_USER}"

read -rp "Build SSH host: " HOST
if [[ -z "$HOST" ]]; then
  echo "Build SSH host is required." >&2
  exit 1
fi

read -rp "Build SSH port [$DEFAULT_PORT]: " PORT
PORT="${PORT:-$DEFAULT_PORT}"

read -rp "Remote deepwork project path [$DEFAULT_PROJECT]: " REMOTE_PROJECT
REMOTE_PROJECT="${REMOTE_PROJECT:-$DEFAULT_PROJECT}"

SERVER="$USER@$HOST"
REMOTE_BINARY="$REMOTE_PROJECT/target/release/deepwork"

echo "Building on $HOST..."
ssh -p "$PORT" "$SERVER" "cd $REMOTE_PROJECT && cargo build --release"

echo "Fetching binary..."
mkdir -p "$LOCAL_BIN"
rsync -ah --info=progress2 --no-i-r --stats \
    -e "ssh -p $PORT" \
    "$SERVER:$REMOTE_BINARY" \
    "$LOCAL_BIN/deepwork"

chmod +x "$LOCAL_BIN/deepwork"
echo "Deployed: $(deepwork --version 2>/dev/null || echo 'deepwork installed to ~/.local/bin/deepwork')"
