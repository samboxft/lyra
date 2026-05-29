#Requires -Version 5.1
# After you pass hCaptcha and create "Lyra" in the Developer Portal (browser),
# run this with your Discord USER token (Developer Portal session — not BOT_TOKEN).
param(
    [Parameter(Mandatory = $false)]
    [string]$UserToken
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$envFile = Join-Path $Root ".env"

if ([string]::IsNullOrWhiteSpace($UserToken)) {
    $secure = Read-Host "Paste Discord USER token (optional; Enter to skip and use browser only)" -AsSecureString
    if ($secure.Length -gt 0) {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $UserToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    }
}

function Get-Apps($token) {
    $h = @{ Authorization = $token.Trim() }
    Invoke-RestMethod -Uri "https://discord.com/api/v10/applications" -Headers $h -Method GET
}

function Set-BotTokenInEnv($botToken) {
    $botToken = $botToken.Trim().Trim('"').Trim("'")
    $null = Invoke-RestMethod -Uri "https://discord.com/api/v10/users/@me" -Headers @{ Authorization = "Bot $botToken" } -TimeoutSec 15
    $lines = Get-Content $envFile
    $out = foreach ($line in $lines) {
        if ($line -match '^\s*BOT_TOKEN\s*=') { "BOT_TOKEN=$botToken" } else { $line }
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($envFile, ($out -join "`n") + "`n", $utf8)
}

if ($UserToken) {
    Write-Host "Waiting for Lyra application (create it in the browser after hCaptcha)..."
    $app = $null
    for ($i = 0; $i -lt 60; $i++) {
        $apps = @(Get-Apps $UserToken)
        $app = $apps | Where-Object { $_.name -eq "Lyra" } | Select-Object -First 1
        if ($app) { break }
        Start-Sleep 5
    }
    if (-not $app) {
        Write-Error "No application named Lyra found. Complete hCaptcha → Create in https://discord.com/developers/applications"
    }
    Write-Host "Found app $($app.id). Resetting bot token..."
    $h = @{ Authorization = $UserToken.Trim(); "Content-Type" = "application/json" }
    $bot = Invoke-RestMethod -Uri "https://discord.com/api/v10/applications/$($app.id)/bot/reset" -Headers $h -Method POST
    Set-BotTokenInEnv $bot.token
    Write-Host "BOT_TOKEN saved. Starting Lyra..."
    & (Join-Path $PSScriptRoot "start-lyra.ps1")
} else {
    Write-Host "Open Developer Portal, pass hCaptcha, create Lyra, then re-run with -UserToken or use set-bot-token.ps1 with the Bot token from Bot → Reset Token."
}
