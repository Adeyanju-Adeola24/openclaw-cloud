#!/usr/bin/env bash
# Start the OpenClaw gateway in a GitHub Codespace.
set -euo pipefail

OPENCLAW_BIN="$HOME/.nvm/current/bin/openclaw"
STATE_DIR="$HOME/.openclaw"
LOG_FILE="$STATE_DIR/logs/gateway.log"

mkdir -p "$STATE_DIR/logs"

if [[ ! -x "$OPENCLAW_BIN" ]]; then
  curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh \
    | bash -s -- --no-onboard
  OPENCLAW_BIN="$HOME/.nvm/current/bin/openclaw"
fi

if curl -fsS --max-time 5 http://127.0.0.1:18789/health >/dev/null 2>&1; then
  echo "OpenClaw gateway is already healthy."
  exit 0
fi

nohup setsid "$OPENCLAW_BIN" gateway run >> "$LOG_FILE" 2>&1 </dev/null &
echo $! > "$STATE_DIR/gateway.pid"

for _ in $(seq 1 60); do
  if curl -fsS --max-time 5 http://127.0.0.1:18789/health >/dev/null 2>&1; then
    echo "OpenClaw gateway is healthy."
    exit 0
  fi
  sleep 2
done

echo "OpenClaw gateway did not become healthy. See $LOG_FILE" >&2
exit 1
