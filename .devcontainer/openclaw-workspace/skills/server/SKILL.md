---
name: server
description: Pause or resume OpenClaw responses and check Gateway status.
user-invocable: true
---

# Server control

Use the `exec` tool for this command. Act only on the explicit argument supplied by the owner.

- `/server status`: Run all three commands and report their results without guessing:
  1. `openclaw gateway status`
  2. `curl -fsS http://127.0.0.1:18789/health`
  3. `openclaw channels status --probe`

  State the exact health response and the exact Telegram probe result. Never infer that Telegram is disconnected when the probe says it is connected.
- `/server off`: Create the marker file `~/.openclaw/server-paused` using a safe Python command. Confirm that OpenClaw is paused and explain that the Gateway remains connected so `/server on` can resume it.
- `/server on`: Remove `~/.openclaw/server-paused` using a safe Python command. Confirm that OpenClaw is active again.
- Unknown arguments: Show the supported forms: `/server on`, `/server off`, and `/server status`.

Do not actually stop the Gateway or the Codespace for `/server off`; that would make the Telegram bot unable to receive `/server on`.
