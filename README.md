# OpenClaw 24/7 on GitHub Actions — $0, no card, unlimited

Runs an OpenClaw gateway on GitHub-hosted runners. Public repos get **unlimited
free Actions minutes**, so this can stay up indefinitely.

## How it stays alive

| Mechanism | Detail |
|---|---|
| Job length | GitHub caps a job at 6 hours |
| Overlap | A new job starts every 4 hours (`cron: '0 */4 * * *'`), so one is always serving |
| State | `~/.openclaw` is stored in the Actions cache and restored on the next job |
| Public access | `cloudflared` tunnel (free). Quick tunnel = random URL per job; named tunnel = stable URL |
| Secrets | Injected from repo secrets at runtime; never written to the config in the cache |

## One-time setup

1. Create a **public** repo and push this folder (public = unlimited free minutes).
2. Add repository secrets: **Settings → Secrets and variables → Actions → New repository secret**
   - `DEEPSEEK_API_KEY`
   - `NVIDIA_API_KEY`
   - `OPENCODE_API_KEY`
   - *(only the providers you actually use)*
3. Open **Actions → OpenClaw 24/7 → Run workflow**.
4. Read the public URL + token from the job log or the run summary.

## Optional: stable URL

Create a free Cloudflare account → Zero Trust → Tunnels → create a named tunnel →
add the token as the `CLOUDFLARE_TUNNEL_TOKEN` secret and the hostname as
`CLOUDFLARE_PUBLIC_URL`. The tunnel then points at `http://127.0.0.1:18789`.

## Notes

- The gateway binds `127.0.0.1` only; the tunnel is the only ingress.
- `memory.search.provider` is `none` (no embedding key needed).
- Each job rebuilds `openclaw.json` with fresh secrets, so sessions/state in the
  cache survive but keys never do.
