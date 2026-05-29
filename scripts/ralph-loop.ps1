#Requires -Version 5.1
# YOLO retry loop: keep trying until Postgres + Lavalink are healthy (or max attempts).
param(
    [int]$MaxAttempts = 30,
    [int]$SleepSeconds = 20
)

$ErrorActionPreference = "Continue"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

function Load-Env {
    Get-Content ".env" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $n = $matches[1].Trim()
            $v = $matches[2].Trim()
            [Environment]::SetEnvironmentVariable($n, $v, 'Process')
        }
    }
}

function Test-Postgres {
    param([string]$PgRoot, [string]$User, [string]$Db)
    $psql = Join-Path $PgRoot "bin\psql.exe"
    if (-not (Test-Path $psql)) { return $false }
    $r = & $psql -U $User -d $Db -tAc "SELECT 1" 2>$null
    return $r -eq "1"
}

function Test-Lavalink {
    param([string]$Password, [int]$Port = 2333)
    try {
        $h = @{ Authorization = $Password }
        $r = Invoke-RestMethod -Uri "http://localhost:$Port/version" -Headers $h -TimeoutSec 5
        return $null -ne $r
    } catch { return $false }
}

function Get-JavaExe {
    $j = Get-Command java -ErrorAction SilentlyContinue
    if ($j) { return $j.Source }
    $p = Join-Path $env:LOCALAPPDATA "jdk-21\bin\java.exe"
    if (Test-Path $p) { return $p }
    Get-ChildItem $env:LOCALAPPDATA -Directory -Filter "jdk*" -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName "bin\java.exe" } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}

Load-Env
$pgRoot = Join-Path $Root "data\postgresql"
$lavalinkDir = Join-Path $Root "lavalink"

for ($i = 1; $i -le $MaxAttempts; $i++) {
    Write-Host "[ralph $i/$MaxAttempts] setup tick $(Get-Date -Format 'HH:mm:ss')"

    try {
        & (Join-Path $PSScriptRoot "setup-windows.ps1") -NoRun 2>&1 | Out-Host
    } catch {
        Write-Warning $_.Exception.Message
    }

    $pgOk = Test-Postgres -PgRoot $pgRoot -User $env:POSTGRES_USER -Db $env:POSTGRES_DB
    if (-not $pgOk) {
        Write-Host "  postgres: not ready"
    } else {
        Write-Host "  postgres: OK"
    }

    $lvOk = Test-Lavalink -Password $env:LAVALINK_SERVER_PASSWORD
    if (-not $lvOk) {
        $java = Get-JavaExe
        if ($java -and (Test-Path (Join-Path $lavalinkDir "Lavalink.jar"))) {
            $existing = Get-Process java -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -like "*jdk*" -or $_.CommandLine -like "*Lavalink*" }
            if (-not $existing) {
                Write-Host "  lavalink: starting..."
                Start-Process -FilePath $java -ArgumentList "-jar", "Lavalink.jar" `
                    -WorkingDirectory $lavalinkDir -WindowStyle Hidden | Out-Null
                Start-Sleep -Seconds 15
            }
        }
        $lvOk = Test-Lavalink -Password $env:LAVALINK_SERVER_PASSWORD
    }
    Write-Host "  lavalink: $(if ($lvOk) { 'OK' } else { 'not ready' })"

    if ($pgOk -and $lvOk) {
        Write-Host "AGENT_LOOP_WAKE_LYRA {\"prompt\":\"Lyra infra ready: postgres and lavalink healthy. If BOT_TOKEN is set in .env, start target\\release\\lyra.exe; otherwise prompt user for Discord bot token.\",\"pg\":true,\"lavalink\":true}"
        exit 0
    }

    Start-Sleep -Seconds $SleepSeconds
}

Write-Host "AGENT_LOOP_WAKE_LYRA {\"prompt\":\"Lyra infra loop exhausted attempts. Check data/pgdata server.log and lavalink logs; report blockers.\",\"pg\":false,\"lavalink\":false}"
exit 1
