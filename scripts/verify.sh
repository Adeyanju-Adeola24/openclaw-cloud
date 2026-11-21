#!/usr/bin/env bash
# Server-side verification. Runs ON the runner - no browser, no local machine.
set -uo pipefail
OC="$HOME/.openclaw"
TOKEN="$(cat "$OC/gateway-token" 2>/dev/null)"
URL="$(cat "$OC/public-url.txt" 2>/dev/null)"
OUT="$OC/verify-result.txt"

{
  echo "OpenClaw cloud verification"
  echo "time: $(date -u +%FT%TZ)"
  echo ""

  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 http://127.0.0.1:18789/health)
  body=$(curl -s --max-time 15 http://127.0.0.1:18789/health)
  echo "local /health      : HTTP $code  $body"

  dcode=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 http://127.0.0.1:18789/)
  dbytes=$(curl -s --max-time 20 http://127.0.0.1:18789/ | wc -c)
  echo "local dashboard    : HTTP $dcode  ${dbytes} bytes"

  if [ -n "$URL" ] && [[ "$URL" == https://* ]]; then
    tcode=$(curl -s -o /dev/null -w '%{http_code}' --max-time 40 "$URL/health")
    tbody=$(curl -s --max-time 40 "$URL/health")
    echo "public /health     : HTTP $tcode  $tbody"
    tcode2=$(curl -s -o /dev/null -w '%{http_code}' --max-time 40 "$URL/")
    echo "public dashboard   : HTTP $tcode2"
  else
    echo "public URL         : (not detected)"
  fi

  echo ""
  echo "websocket probe    :"
  node - <<'NODE' || true
const token = process.env.OPENCLAW_DASHBOARD_TOKEN || '';
const cands = ['/ws', '/control', '/control-ui', '/gateway', '/rpc', '/socket', '/'];
const headers = { Authorization: `Bearer ${token}` };
(async () => {
  for (const path of cands) {
    const url = `ws://127.0.0.1:18789${path}?token=${encodeURIComponent(token)}`;
    try {
      const ws = new WebSocket(url, { headers });
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('timeout')), 9000);
        ws.onopen = () => { clearTimeout(timer); resolve(); };
        ws.onerror = (e) => { clearTimeout(timer); reject(new Error(e.message || 'error')); };
      });
      console.log(`  OK    ${path}`);
      try { ws.close(); } catch {}
      break;
    } catch (err) {
      console.log(`  fail  ${path} (${err.message})`);
    }
  }
})();
NODE

  echo ""
  echo "processes:"
  ps -eo pid,rss,etime,cmd --sort=-rss | grep -E 'openclaw|cloudflared' | grep -v grep | head -8 | awk '{printf "  pid=%s rss=%sKB up=%s %s\n", $1,$2,$3,$4" "$5}'
  echo ""
  echo "memory:"
  free -h | head -2
} > "$OUT" 2>&1

cat "$OUT"
