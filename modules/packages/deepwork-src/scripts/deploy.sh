#!/usr/bin/env bash
set -euo pipefail

SERVER="USER@HOST"
PORT=22
REMOTE_PROJECT="~/projects/deepwork"
REMOTE_BINARY="$REMOTE_PROJECT/target/release/deepwork"
LOCAL_BIN="$HOME/.local/bin"

echo "Building on USER_DEFINED_SSH_HOST..."
ssh -p "$PORT" "$SERVER" "cd $REMOTE_PROJECT && cargo build --release"

echo "Fetching binary..."
mkdir -p "$LOCAL_BIN"
rsync -ah --info=progress2 --no-i-r --stats \
    -e "ssh -p $PORT" \
    "$SERVER:$REMOTE_BINARY" \
    "$LOCAL_BIN/deepwork"

chmod +x "$LOCAL_BIN/deepwork"
echo "Deployed: $(deepwork --version 2>/dev/null || echo 'deepwork installed to ~/.local/bin/deepwork')"
