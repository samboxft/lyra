#Requires -Version 5.1
<#
.SYNOPSIS
  Clean setup from BOT_TOKEN: validate token, start services, run Lyra.

.DESCRIPTION
  1. Ensures .env exists
  2. Prompts for bot token if missing/invalid (or pass -Token)
  3. Starts Postgres + Lavalink if needed
  4. Builds release binary if missing (optional -Build)
  5. Starts Lyra
#>
param(
    [string]$Token,
    [switch]$Build
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Created .env from .env.example"
}

function Get-BotTokenFromEnv {
    $line = Get-Content ".env" | Where-Object { $_ -match '^\s*BOT_TOKEN\s*=' } | Select-Object -First 1
    if (-not $line) { return $null }
    ($line -split '=', 2)[1].Trim().Trim('"').Trim("'")
}

function Test-BotToken([string]$t) {
    if ([string]::IsNullOrWhiteSpace($t) -or $t -match 'REPLACE_WITH') { return $false }
    try {
        $null = Invoke-RestMethod "https://discord.com/api/v10/users/@me" -Headers @{ Authorization = "Bot $t" } -TimeoutSec 10
        return $true
    } catch { return $false }
}

if ($Token) {
    & (Join-Path $PSScriptRoot "set-bot-token.ps1") -Token $Token
} else {
    $existing = Get-BotTokenFromEnv
    if (-not (Test-BotToken $existing)) {
        Write-Host @"

=== Discord bot token required ===
1. Open https://discord.com/developers/applications
2. Select your app (e.g. Lyra) -> Bot -> Reset Token -> Copy
3. Paste below (input is hidden)

"@
        & (Join-Path $PSScriptRoot "set-bot-token.ps1")
    } else {
        Write-Host "BOT_TOKEN in .env is valid."
    }
}

if ($Build -or -not (Test-Path "target\release\lyra.exe")) {
    Write-Host "Building lyra (release)..."
    & (Join-Path $PSScriptRoot "build.ps1")
}

& (Join-Path $PSScriptRoot "start-lyra.ps1")
