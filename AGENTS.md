# Working on this repo in the Base44 sandbox

Non-obvious things learned while getting this stack running. See `README.md` for
the project's own documentation.

## What runs here

`docker compose -f docker-compose.base44.yml up -d` starts:

| Service | Role |
| --- | --- |
| `db` | PostgreSQL 17, database `lyra` / user `lyra` |
| `lavalink-plugins-init` | One-shot: hands `/opt/Lavalink/plugins` to uid 322 |
| `lavalink` | Lavalink v4 audio node (plugins downloaded on first start) |
| `lyra` | The bot itself, built from this checkout and run in the foreground |
| `status` | Read-only status page on host port 3000 |

**The app has no web UI.** Λύρα is a headless Discord client: it talks to the
Discord gateway and Lavalink, and has no HTTP interface at all. Port 3000 is
therefore served by `base44/status/server.py`, a small companion process that
reports whether the bot binary is alive, whether Lavalink answers `/version`,
whether Postgres accepts connections, and the bot's log tail. It is a viewer for
the bot, not a feature of the bot — do not treat it as the application.

## Credentials

`BOT_TOKEN` is the only value that must come from the user (Discord Developer
Portal → Bot → Reset Token). `.env.base44-defaults` holds a clearly fake
placeholder so the stack still boots; the platform's real value arrives in
`/run/base44/app.env`, which is loaded **after** that file so it wins.

Without a valid token the bot exits with code 101 and logs
`401: Unauthorized` — that is the expected state, not a compose defect.

Spotify / Deezer / YouTube-OAuth values are optional; without them the bot plays
YouTube and SoundCloud through the stock Lavalink sources.

## Gotchas

- **Lavalink plugin volume ownership.** Lavalink runs as uid 322 and downloads
  plugin jars into `/opt/Lavalink/plugins`. A fresh named volume is root-owned,
  so the `lavalink-plugins-init` service chowns it first. Removing that service
  brings back `Permission denied` on first start.
- **Rust build times.** The first build is ~2 minutes; artifacts live in the
  `lyra-target` named volume, so later runs are near-instant. Deleting that
  volume forces a full rebuild.
- **No live reload.** The container runs `cargo build --locked` and then the
  binary. After changing Rust source, restart the service to rebuild:
  `docker compose -f docker-compose.base44.yml restart lyra`, then reload the
  preview.
- **Compile-time SQL.** `sqlx::query!` macros need the committed `.sqlx` data;
  `SQLX_OFFLINE=true` is set for that reason. Changing a query means
  regenerating `.sqlx` with a live `DATABASE_URL`.
- **Migrations are embedded** (`sqlx::migrate!("../migrations")`) and run on
  every bot start, so no separate migration step exists.
- **Bot healthcheck** matches the running binary via `/proc/*/exe`; matching the
  command line instead gives a false "healthy" while `cargo build` runs.

## Verifying

```console
docker compose -f docker-compose.base44.yml ps
docker compose -f docker-compose.base44.yml logs -f lyra
curl -s localhost:3000/api/status
docker exec lyra-db-1 psql -U lyra -d lyra -c '\dt'   # migrations applied
```

Run checks inside the container (the sandbox host has no Rust toolchain):

```console
docker compose -f docker-compose.base44.yml exec -T lyra cargo test --locked
```
