#!/usr/bin/env bash
# OpenClaw gateway on a GitHub-hosted runner.
# Secrets are injected at runtime (never committed); the gateway config is
# rebuilt on every job so tokens are never written into the Actions cache.
set -uo pipefail

OC="$HOME/.openclaw"
mkdir -p "$OC/tmp/openclaw"
export NODE_OPTIONS="--max-old-space-size=1024"

echo "== writing gateway config =="
TOKEN_FILE="$OC/gateway-token"
# A stable token comes from the repo secret so it survives across jobs and is
# never written into the public repo. Fall back to a generated one.
if [ -n "${OPENCLAW_DASHBOARD_TOKEN:-}" ]; then
  printf '%s' "$OPENCLAW_DASHBOARD_TOKEN" > "$TOKEN_FILE"
else
  if [ ! -f "$TOKEN_FILE" ]; then
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TOKEN_FILE"
  fi
fi
export OPENCLAW_TOKEN_VALUE
OPENCLAW_TOKEN_VALUE="$(cat "$TOKEN_FILE")"

python3 - <<'PY'
import json, os, pathlib
oc = pathlib.Path.home() / ".openclaw"
cfgp = oc / "openclaw.json"
cfg = json.loads(cfgp.read_text()) if cfgp.exists() else {}

gw = cfg.setdefault("gateway", {})
gw.update({
    "mode": "local",
    "auth": {"mode": "token", "token": os.environ["OPENCLAW_TOKEN_VALUE"]},
    "port": 18789,
    "bind": "loopback",
    "trustedProxies": ["127.0.0.1"],
    "controlUi": {
        "allowedOrigins": ["http://127.0.0.1:3000"],
        "dangerouslyAllowHostHeaderOriginFallback": True,
    },
})
cfg.setdefault("memory", {})["search"] = {"provider": "none"}

providers = {}
if os.environ.get("DEEPSEEK_API_KEY"):
    providers["deepseek"] = {
        "baseUrl": "https://api.deepseek.com/v1",
        "apiKey": os.environ["DEEPSEEK_API_KEY"],
        "api": "openai-completions",
    }
if os.environ.get("NVIDIA_API_KEY"):
    providers["nvidia"] = {
        "baseUrl": "https://integrate.api.nvidia.com/v1",
        "apiKey": os.environ["NVIDIA_API_KEY"],
        "api": "openai-completions",
    }
if os.environ.get("OPENCODE_API_KEY"):
    providers["opencode"] = {
        "baseUrl": "https://opencode.ai/zen/v1",
        "apiKey": os.environ["OPENCODE_API_KEY"],
        "api": "openai-completions",
    }
if providers:
    cfg.setdefault("models", {})["providers"] = providers

cfgp.write_text(json.dumps(cfg, indent=2))
print("providers configured:", ", ".join(providers) or "(none - add repo secrets)")
PY

echo "== starting gateway =="
pkill -f 'openclaw/dist/index.js gateway' 2>/dev/null || true
pkill -f 'cloudflared tunnel' 2>/dev/null || true
sleep 2

nohup openclaw gateway --port 18789 > "$OC/gateway.log" 2>&1 &
echo "gateway pid $!"

echo "== waiting for the gateway to bind (runner CPU is slow) =="
ready=0
for i in $(seq 1 120); do
  sleep 5
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1:18789/health 2>/dev/null)"
  if [ "$code" = "200" ]; then
    ready=1
    echo "gateway healthy after ~$((i*5))s"
    break
  fi
  if [ $((i % 12)) -eq 0 ]; then
    echo "  ...still booting ($((i*5))s) last log:"
    tail -n 3 "$OC/gateway.log" | sed 's/^/    /'
  fi
done

if [ "$ready" != "1" ]; then
  echo "!! gateway did not become healthy; last 30 log lines:"
  tail -n 30 "$OC/gateway.log"
fi

echo "== starting public tunnel =="
if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  # Named tunnel -> stable hostname you chose in the Cloudflare dashboard
  nohup cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN" \
    > "$OC/tunnel.log" 2>&1 &
  URL="${CLOUDFLARE_PUBLIC_URL:-}"
  echo "named tunnel started (set CLOUDFLARE_PUBLIC_URL secret to record the hostname)"
else
  # Quick tunnel -> random hostname, printed below
  nohup cloudflared tunnel --url http://127.0.0.1:18789 \
    --http-host-header 127.0.0.1:18789 --no-autoupdate > "$OC/tunnel.log" 2>&1 &
  URL=""
  for i in $(seq 1 30); do
    sleep 3
    URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$OC/tunnel.log" 2>/dev/null | head -1)"
    [ -n "$URL" ] && break
  done
fi

if [ -n "$URL" ]; then
  echo "$URL" > "$OC/public-url.txt"
else
  echo "(no quick-tunnel URL detected - check $OC/tunnel.log)" > "$OC/public-url.txt"
fi

cat > "$OC/keepalive.sh" <<'KEEP'
#!/usr/bin/env bash
OC="$HOME/.openclaw"
while true; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:18789/health 2>/dev/null)"
  if [ "$code" != "200" ]; then
    pkill -f 'openclaw/dist/index.js gateway' 2>/dev/null
    sleep 5
    nohup openclaw gateway --port 18789 >> "$OC/gateway.log" 2>&1 &
  fi
  if ! pgrep -f 'cloudflared tunnel' >/dev/null 2>&1; then
    nohup cloudflared tunnel --url http://127.0.0.1:18789 \
      --http-host-header 127.0.0.1:18789 --no-autoupdate >> "$OC/tunnel.log" 2>&1 &
  fi
  sleep 120
done
KEEP
chmod +x "$OC/keepalive.sh"
nohup bash "$OC/keepalive.sh" > "$OC/keepalive.log" 2>&1 &

echo ""
echo "===================================================="
echo " OPENCLAW IS LIVE"
echo "===================================================="
echo " Public URL : $(cat "$OC/public-url.txt")"
echo " Token      : $(cat "$TOKEN_FILE")"
echo " Health     : http://127.0.0.1:18789/health"
echo "===================================================="

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## OpenClaw is live"
    echo ""
    echo "**Public URL:** $(cat "$OC/public-url.txt")"
    echo ""
    echo "**Token:** \`$(cat "$TOKEN_FILE")\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi
