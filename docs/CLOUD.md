# Run Lyra online (24/7)

Lyra needs three pieces: **Discord bot** (this repo), **PostgreSQL**, and **Lavalink**. The easiest hosted setup is [Railway](https://railway.app).

## Railway (recommended)

### 1. Create project

1. Open https://railway.app/new
2. **Deploy from GitHub repo** → `samboxft/lyra` (or your fork)
3. Or locally: `railway init` then `railway add` (see below)

### 2. Add services

| Service   | Type              | Notes |
|-----------|-------------------|--------|
| Postgres  | Database → PostgreSQL | Railway sets `DATABASE_URL` |
| lavalink  | Docker image `ghcr.io/lavalink-devs/lavalink:4` | See variables below |
| lyra      | Same repo, uses root `Dockerfile` | Bot process |

### 3. Variables

**lavalink** service:

- `LAVALINK_SERVER_PASSWORD` — strong random string (same as on lyra)
- `_JAVA_OPTIONS` — `-Xmx1G`
- Mount or bake `lavalink/application.yml` (repo file works as bind in Compose; on Railway set env from compose.cloud.yaml or use default image config)

**lyra** service (required):

| Variable | Value |
|----------|--------|
| `BOT_TOKEN` | Discord Developer Portal → Bot → token |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` (reference) |
| `SERVER_ADDRESS` | `lavalink` (private DNS name of Lavalink service) |
| `SERVER_PORT` | `2333` |
| `LAVALINK_SERVER_PASSWORD` | same as lavalink service |
| `SQLX_OFFLINE` | `true` |

### 4. Deploy

Push to `main` with GitHub connected, or run:

```bash
railway up --service lyra
```

### 5. Invite bot

https://discord.com/api/oauth2/authorize?client_id=YOUR_APPLICATION_ID&permissions=36700160&scope=bot%20applications.commands

---

## Repo links

- Source: https://github.com/samboxft/lyra
- Upstream: https://github.com/lyra-music/lyra (GPL-3.0)

## Cost note

Lavalink + Postgres + bot typically need a paid Railway plan or ~$5–15/mo usage. Free trial credits apply for new accounts.
