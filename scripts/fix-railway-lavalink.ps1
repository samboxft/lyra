# Fix Lyra bot -> Lavalink networking on Railway (private DNS).
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host 'Setting SERVER_ADDRESS=lyra-lavalink.railway.internal on lyra-bot...'
railway variable set SERVER_ADDRESS=lyra-lavalink.railway.internal --service lyra-bot

Write-Host 'Redeploying lyra-bot...'
railway up --detach --service lyra-bot

Write-Host 'Done. Check logs: railway logs --service lyra-bot --lines 40'
