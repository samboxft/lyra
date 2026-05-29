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

Invite bot:  
https://discord.com/api/oauth2/authorize?client_id=1509838015856640011&permissions=36700160&scope=bot%20applications.commands

## Local alternative

```powershell
cd lyra-main
.\scripts\redo-from-token.ps1
```
