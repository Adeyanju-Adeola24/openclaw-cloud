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

persist_env_secret() {
  local name="$1"
  local value="$2"
  local tmp

  tmp="$(mktemp "$STATE_DIR/.env.tmp.XXXXXX")"
  if [[ -f "$STATE_DIR/.env" ]]; then
    grep -v "^${name}=" "$STATE_DIR/.env" > "$tmp" || true
  fi
  printf '%s=%s\n' "$name" "$value" >> "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$STATE_DIR/.env"
}

if [[ -n "${OPENCLAW_DASHBOARD_TOKEN:-}" ]]; then
  persist_env_secret OPENCLAW_DASHBOARD_TOKEN "$OPENCLAW_DASHBOARD_TOKEN"
fi

if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  persist_env_secret TELEGRAM_BOT_TOKEN "$TELEGRAM_BOT_TOKEN"
fi

if [[ ! -x "$OPENCLAW_BIN" ]]; then
  curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh \
    | bash -s -- --no-onboard
  OPENCLAW_BIN="$HOME/nvm/current/bin/openclaw"
fi

if ! "$OPENCLAW_BIN" plugins inspect duckduckgo >/dev/null 2>&1; then
  "$OPENCLAW_BIN" plugins install @openclaw/duckduckgo-plugin \
    || echo "Warning: DuckDuckGo search plugin could not be installed." >&2
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

if [[ -n "${NVIDIA_API_KEY:-}" ]]; then
  # Prefer the Codespaces-injected secret over a potentially stale saved profile.
  "$OPENCLAW_BIN" config set models.providers.nvidia.apiKey '"NVIDIA_API_KEY"' --strict-json >/dev/null || true

  # The auth store is only mutable while the Gateway is offline. Remove the
  # stale profile so the current Codespaces secret is the credential in use.
  if ! curl -fsS --max-time 5 http://127.0.0.1:18789/health >/dev/null 2>&1; then
    "$OPENCLAW_BIN" models auth logout nvidia:default --yes --agent main >/dev/null 2>&1 || true
  fi
fi

"$OPENCLAW_BIN" config set tools.web.search.enabled true --strict-json >/dev/null || true
"$OPENCLAW_BIN" config set tools.web.search.provider '"duckduckgo"' --strict-json >/dev/null || true
"$OPENCLAW_BIN" config set tools.web.search.maxResults 5 --strict-json >/dev/null || true
"$OPENCLAW_BIN" config set plugins.entries.duckduckgo.config.webSearch.region '"ng-en"' --strict-json >/dev/null || true
"$OPENCLAW_BIN" config set plugins.entries.duckduckgo.config.webSearch.safeSearch '"moderate"' --strict-json >/dev/null || true

if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  "$OPENCLAW_BIN" config set channels.telegram.enabled true --strict-json >/dev/null || true
  "$OPENCLAW_BIN" config set channels.telegram.dmPolicy '"pairing"' --strict-json >/dev/null || true
  "$OPENCLAW_BIN" config set channels.telegram.botToken \
    --ref-provider default --ref-source env --ref-id TELEGRAM_BOT_TOKEN >/dev/null || true

  if ! "$OPENCLAW_BIN" config get bindings 2>/dev/null | grep -q '"telegram"'; then
    "$OPENCLAW_BIN" config set bindings \
      '[{"agentId":"main","match":{"channel":"telegram","accountId":"default"}}]' \
      --strict-json >/dev/null || true
  fi
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
