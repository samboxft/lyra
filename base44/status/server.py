"""Read-only status page for the Λύρα bot.

The bot is a headless Discord client, so this companion process gives the
sandbox preview something to show: whether the bot process is alive, whether
Lavalink and PostgreSQL answer, and the tail of the bot's own log.

Standard library only; runs in python:3.12-slim.
"""

import json
import os
import re
import socket
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

LOG_PATH = os.environ.get("LOG_PATH", "/var/log/lyra/lyra.log")
HEARTBEAT_PATH = os.environ.get("HEARTBEAT_PATH", "/var/log/lyra/heartbeat")
STATE_PATH = os.environ.get("STATE_PATH", "/var/log/lyra/state")
LAVALINK_URL = os.environ.get("LAVALINK_URL", "http://lavalink:2333").rstrip("/")
LAVALINK_PASSWORD = os.environ.get("LAVALINK_PASSWORD", "")
DB_HOST = os.environ.get("DB_HOST", "db")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
PORT = int(os.environ.get("PORT", "8000"))

ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def read_log(limit=80):
    try:
        with open(LOG_PATH, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - 64_000))
            lines = handle.read().decode("utf-8", "replace").splitlines()
        # The bot colourises its tracing output; the browser shows the escapes.
        return [
            ANSI_ESCAPE.sub("", line).rstrip() for line in lines if line.strip()
        ][-limit:]
    except FileNotFoundError:
        return []


def bot_state():
    """The bot container writes `running` / `exited:<code>` plus a heartbeat
    while the binary lives, so a crash-restart loop never reads as healthy."""
    state, exit_code = "unknown", None
    try:
        parts = open(STATE_PATH).read().split()
        if parts[0].startswith("exited:"):
            state, exit_code = "exited", int(parts[0].split(":", 1)[1])
        elif parts[0] == "running":
            state = "running"
    except (FileNotFoundError, IndexError, ValueError):
        pass

    try:
        with open(HEARTBEAT_PATH) as handle:
            beat_age = int(time.time()) - int(handle.read().strip())
    except (FileNotFoundError, ValueError):
        beat_age = None

    alive = state == "running" and beat_age is not None and beat_age < 30
    return {"alive": alive, "state": state, "exit_code": exit_code, "beat_age": beat_age}


def lavalink_state():
    request = urllib.request.Request(
        f"{LAVALINK_URL}/version",
        headers={"Authorization": LAVALINK_PASSWORD},
    )
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            # Lavalink answers /version with a bare semver string.
            version = response.read().decode().strip() or "unknown"
        return {"reachable": True, "version": version}
    except Exception as error:  # noqa: BLE001 - reported to the page
        return {"reachable": False, "error": type(error).__name__}


def db_state():
    try:
        with socket.create_connection((DB_HOST, DB_PORT), timeout=3):
            return {"reachable": True}
    except OSError as error:
        return {"reachable": False, "error": type(error).__name__}


def snapshot():
    log = read_log()
    bot = bot_state()
    if not bot["alive"] and any("401: Unauthorized" in line for line in log):
        bot["hint"] = "Discord rejected the configured token (401). Set a real BOT_TOKEN."

    return {
        "bot": bot,
        "lavalink": lavalink_state(),
        "database": db_state(),
        "log": log,
        "checked_at": time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()),
    }


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Λύρα — bot status</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; padding: 32px 20px 48px;
    background: #12131a; color: #e6e7ee;
    font: 15px/1.5 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
  }
  main { max-width: 900px; margin: 0 auto; }
  h1 { margin: 0 0 4px; font-size: 23px; letter-spacing: -0.01em; }
  h1 span { color: #8ab4ff; }
  .sub { margin: 0 0 26px; color: #9aa0b4; font-size: 13px; }
  .cards { display: grid; gap: 12px; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); }
  .card { background: #1b1d27; border: 1px solid #272a38; border-radius: 12px; padding: 14px 16px; }
  .card h2 { margin: 0 0 8px; font-size: 12px; text-transform: uppercase; letter-spacing: .08em; color: #9aa0b4; font-weight: 600; }
  .state { display: flex; align-items: center; gap: 8px; font-size: 15px; font-weight: 600; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: #6b7280; flex: none; }
  .ok .dot { background: #34d399; box-shadow: 0 0 0 3px rgba(52,211,153,.18); }
  .bad .dot { background: #f87171; box-shadow: 0 0 0 3px rgba(248,113,113,.18); }
  .wait .dot { background: #fbbf24; box-shadow: 0 0 0 3px rgba(251,191,36,.18); }
  .meta { margin-top: 6px; font-size: 12.5px; color: #8b91a6; word-break: break-word; }
  .logs { margin-top: 22px; background: #0e0f16; border: 1px solid #272a38; border-radius: 12px; overflow: hidden; }
  .logs header { display: flex; justify-content: space-between; padding: 10px 14px; font-size: 12px; text-transform: uppercase; letter-spacing: .08em; color: #9aa0b4; background: #151722; border-bottom: 1px solid #272a38; }
  pre { margin: 0; padding: 14px; max-height: 62vh; overflow: auto; font: 12.5px/1.55 ui-monospace, SFMono-Regular, Menlo, monospace; color: #c7ccdb; white-space: pre-wrap; word-break: break-word; }
  .empty { color: #6f768c; }
</style>
</head>
<body>
<main>
  <h1>Λύρα <span>· live bot status</span></h1>
  <p class="sub">A self-hostable Discord music bot. This page reports the bot process, its audio node and its database.</p>

  <section class="cards">
    <div class="card" id="bot"><h2>Bot process</h2><div class="state"><span class="dot"></span><span class="label">Checking…</span></div><div class="meta"></div></div>
    <div class="card" id="lavalink"><h2>Lavalink audio node</h2><div class="state"><span class="dot"></span><span class="label">Checking…</span></div><div class="meta"></div></div>
    <div class="card" id="database"><h2>PostgreSQL</h2><div class="state"><span class="dot"></span><span class="label">Checking…</span></div><div class="meta"></div></div>
  </section>

  <section class="logs">
    <header><span>Bot log tail</span><span id="checked">—</span></header>
    <pre id="log" class="empty">Waiting for the bot to start…</pre>
  </section>
</main>
<script>
  const setCard = (id, cls, label, meta) => {
    const card = document.getElementById(id);
    card.className = "card " + cls;
    card.querySelector(".label").textContent = label;
    card.querySelector(".meta").textContent = meta || "";
  };

  async function refresh() {
    try {
      const res = await fetch("/api/status", { cache: "no-store" });
      const data = await res.json();

      if (data.bot.alive) setCard("bot", "ok", "Running", "Heartbeat " + data.bot.beat_age + "s ago");
      else if (data.bot.state === "exited") setCard("bot", "bad", "Not running", data.bot.hint || ("Exited with code " + data.bot.exit_code + " — see the log below"));
      else setCard("bot", "wait", "Starting", "Compiling the bot, or waiting for it to connect");

      if (data.lavalink.reachable) setCard("lavalink", "ok", "Connected", "Lavalink " + data.lavalink.version);
      else setCard("lavalink", "bad", "Unreachable", data.lavalink.error || "");

      if (data.database.reachable) setCard("database", "ok", "Reachable", "db:5432 accepting connections");
      else setCard("database", "bad", "Unreachable", data.database.error || "");

      const log = document.getElementById("log");
      if (data.log.length) {
        const atBottom = log.scrollTop + log.clientHeight >= log.scrollHeight - 24;
        log.className = "";
        log.textContent = data.log.join("\\n");
        if (atBottom) log.scrollTop = log.scrollHeight;
      }
      document.getElementById("checked").textContent = "updated " + data.checked_at;
    } catch (err) {
      setCard("bot", "bad", "Status unavailable", String(err));
    }
  }

  refresh();
  setInterval(refresh, 3000);
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, status, body, content_type):
        payload = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        route = urlsplit(self.path).path
        if route == "/":
            self._send(200, PAGE, "text/html; charset=utf-8")
        elif route == "/api/status":
            self._send(200, json.dumps(snapshot()), "application/json")
        elif route == "/healthz":
            self._send(200, "ok", "text/plain; charset=utf-8")
        elif route == "/favicon.ico":
            self._send(204, "", "image/x-icon")
        else:
            self._send(404, "not found", "text/plain; charset=utf-8")

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"status page listening on :{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
