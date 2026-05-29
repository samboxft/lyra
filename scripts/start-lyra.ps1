#Requires -Version 5.1
# Start Lyra after BOT_TOKEN is set in .env
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
    }
}

if ($env:BOT_TOKEN -match 'REPLACE_WITH' -or [string]::IsNullOrWhiteSpace($env:BOT_TOKEN)) {
    Write-Error "Set BOT_TOKEN in .env first (Discord Developer Portal → your app → Bot → Reset Token)."
}

$pg = Join-Path $Root "data\pgsql\bin"
if (-not (Get-NetTCPConnection -LocalPort 5432 -State Listen -ErrorAction SilentlyContinue)) {
    $dataDir = Join-Path $Root "data\pgdata"
    Start-Process -FilePath (Join-Path $pg "pg_ctl.exe") -ArgumentList @('-D', $dataDir, 'start', '-w') -Wait -NoNewWindow
}

$java = "$env:LOCALAPPDATA\jdk-21\bin\java.exe"
if (-not (Test-Path $java)) { $java = (Get-Command java -ErrorAction SilentlyContinue).Source }
if ($java) {
    $lv = try { Invoke-RestMethod "http://localhost:2333/version" -Headers @{Authorization=$env:LAVALINK_SERVER_PASSWORD} -TimeoutSec 2 } catch { $null }
    if (-not $lv) {
        Start-Process $java -ArgumentList "-jar","Lavalink.jar" -WorkingDirectory (Join-Path $Root "lavalink") -WindowStyle Hidden
        Start-Sleep 15
    }
}

Write-Host "Starting Lyra bot..."
& (Join-Path $Root "target\release\lyra.exe")
