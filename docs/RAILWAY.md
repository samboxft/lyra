# Lyra on Railway

Dashboard: https://railway.com/project/116492c2-5388-405f-bcf1-5411a602049d

## Services

| Service | Role |
|---------|------|
| **lyra-bot** | Discord bot (needs `BOT_TOKEN`) |
| **lyra-lavalink** | Audio server |
| **Postgres** | Database |

## Required: set BOT_TOKEN

1. [Discord Developer Portal](https://discord.com/developers/applications) → your app → **Bot** → **Reset Token**
2. Railway → **lyra-bot** → **Variables** → add `BOT_TOKEN` (no quotes)
3. Redeploy **lyra-bot** (or wait for auto-restart)

## Required: Lavalink hostname (fixes `/play` timeout)

In **lyra-bot** → **Variables**, set:

| Variable | Value |
|----------|--------|
| `SERVER_ADDRESS` | `lyra-lavalink.railway.internal` |
| `SERVER_PORT` | `2333` |
| `LAVALINK_SERVER_PASSWORD` | same as **lyra-lavalink** service |

Then redeploy **lyra-bot**.

## Invite Lyra1 bot

Developer Portal → **Lyra1** → **OAuth2** → **URL Generator** → scopes `bot` + `applications.commands`.

Or replace `YOUR_APP_ID` in:

`https://discord.com/api/oauth2/authorize?client_id=YOUR_APP_ID&permissions=36700160&scope=bot%20applications.commands`

(Application ID is on **General Information**, not the bot user id.)

## Local alternative

```powershell
cd lyra-main
.\scripts\redo-from-token.ps1
```
