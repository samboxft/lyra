#Requires -Version 5.1
# Start Lyra after BOT_TOKEN is set in .env
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        $val = $matches[2].Trim().Trim('"').Trim("'")
        [Environment]::SetEnvironmentVariable($matches[1].Trim(), $val, 'Process')
    }
}

if ($env:BOT_TOKEN -match 'REPLACE_WITH' -or [string]::IsNullOrWhiteSpace($env:BOT_TOKEN)) {
    Write-Error "Set BOT_TOKEN in .env first (Discord Developer Portal → your app → Bot → Reset Token)."
}

function Get-PostgresBin {
    foreach ($rel in @("data\pgsql\bin", "data\postgresql\bin")) {
        $dir = Join-Path $Root $rel
        if (Test-Path (Join-Path $dir "pg_ctl.exe")) { return $dir }
    }
    return $null
}

function Wait-Lavalink {
    param([string]$Password, [int]$TimeoutSec = 90)
    $headers = @{ Authorization = $Password }
    for ($i = 0; $i -lt $TimeoutSec; $i++) {
        try {
            $null = Invoke-RestMethod "http://localhost:2333/version" -Headers $headers -TimeoutSec 3
            return
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    throw "Lavalink did not respond on http://localhost:2333 within ${TimeoutSec}s."
}

$pgBin = Get-PostgresBin
if ($pgBin -and -not (Get-NetTCPConnection -LocalPort 5432 -State Listen -ErrorAction SilentlyContinue)) {
    $dataDir = Join-Path $Root "data\pgdata"
    Start-Process -FilePath (Join-Path $pgBin "pg_ctl.exe") -ArgumentList @('-D', $dataDir, 'start', '-w') -Wait -NoNewWindow
}

$lavalinkPwd = if ($env:LAVALINK_SERVER_PASSWORD) { $env:LAVALINK_SERVER_PASSWORD } else { "lyra_dev_password" }
try {
    Wait-Lavalink -Password $lavalinkPwd -TimeoutSec 3
} catch {
    $java = "$env:LOCALAPPDATA\jdk-21\bin\java.exe"
    if (-not (Test-Path $java)) { $java = (Get-Command java -ErrorAction SilentlyContinue).Source }
    if (-not $java) { throw "Java not found. Install JDK 21+ for Lavalink." }
    Start-Process $java -ArgumentList "-jar", "Lavalink.jar" -WorkingDirectory (Join-Path $Root "lavalink") -WindowStyle Hidden
    Write-Host "Waiting for Lavalink..."
    Wait-Lavalink -Password $lavalinkPwd
}

Write-Host "Starting Lyra bot..."
& (Join-Path $Root "target\release\lyra.exe")
