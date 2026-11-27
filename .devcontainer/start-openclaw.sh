#!/usr/bin/env bash
# Start the OpenClaw gateway in a GitHub Codespace.
set -euo pipefail

OPENCLAW_BIN="$HOME/nvm/current/bin/openclaw"
STATE_DIR="$HOME/.openclaw"
LOG_FILE="$STATE_DIR/logs/gateway.log"

export PATH="$HOME/nvm/current/bin:$PATH"
umask 077
mkdir -p "$STATE_DIR/logs"
chmod go-w "$HOME/.cache" 2>/dev/null || true

if [[ -n "${OPENCLAW_DASHBOARD_TOKEN:-}" ]]; then
  touch "$STATE_DIR/.env"
  chmod 600 "$STATE_DIR/.env"
  if ! grep -q '^OPENCLAW_DASHBOARD_TOKEN=' "$STATE_DIR/.env"; then
    printf 'OPENCLAW_DASHBOARD_TOKEN=%s\n' "$OPENCLAW_DASHBOARD_TOKEN" >> "$STATE_DIR/.env"
  fi
fi

if [[ ! -x "$OPENCLAW_BIN" ]]; then
  curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh \
    | bash -s -- --no-onboard
  OPENCLAW_BIN="$HOME/nvm/current/bin/openclaw"
fi

if [[ ! -f "$STATE_DIR/openclaw.json" ]]; then
  if [[ -z "${NVIDIA_API_KEY:-}" ]]; then
    echo "NVIDIA_API_KEY is not available to this Codespace." >&2
    exit 1
  fi

  onboard_args=(
    --non-interactive
    --accept-risk
    --auth-choice nvidia-api-key
    --nvidia-api-key "$NVIDIA_API_KEY"
    --flow manual
    --no-install-daemon
    --gateway-auth token
    --gateway-bind loopback
    --gateway-port 18789
    --skip-channels
    --skip-search
    --skip-skills
    --skip-ui
    --skip-health
    --suppress-gateway-token-output
  )

  if [[ -n "${OPENCLAW_DASHBOARD_TOKEN:-}" ]]; then
    onboard_args+=(--gateway-token "$OPENCLAW_DASHBOARD_TOKEN")
  fi

  "$OPENCLAW_BIN" onboard "${onboard_args[@]}"
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
