#Requires -Version 5.1
<#
.SYNOPSIS
  Prepare and run Lyra on Windows (local development).

.DESCRIPTION
  - Ensures build tools are on PATH (Rust, Git, MSVC via vcvars, CMake, NASM)
  - Downloads Lavalink.jar when missing
  - Initializes a portable PostgreSQL data directory under data/pgdata
  - Starts PostgreSQL and Lavalink, then runs the bot

  Edit .env first and set BOT_TOKEN to your Discord bot token.
#>
param(
    [switch]$BuildOnly,
    [switch]$NoRun
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

Set-Location $Root

function Import-VcVars {
    $vcvars = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) {
        $vcvars = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    }
    if (Test-Path $vcvars) {
        cmd /c "`"$vcvars`" && set" | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
            }
        }
    }
}

function Add-ToolPaths {
    $extra = @(
        "$env:USERPROFILE\.cargo\bin",
        "$env:LOCALAPPDATA\PortableGit\cmd",
        "$env:LOCALAPPDATA\cmake\cmake-4.0.2-windows-x86_64\bin",
        "$env:LOCALAPPDATA\nasm\nasm-2.16.03",
        "$env:LOCALAPPDATA\jdk-21\bin"
    )
    foreach ($p in $extra) {
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
            $env:Path = "$p;$env:Path"
        }
    }
}

function Ensure-EnvFile {
    if (-not (Test-Path ".env")) {
        Copy-Item ".env.example" ".env"
        Write-Host "Created .env from .env.example — set BOT_TOKEN before running the bot."
    }
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"').Trim("'")
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }
}

function Ensure-Lavalink {
    $dir = Join-Path $Root "lavalink"
    $jar = Join-Path $dir "Lavalink.jar"
    if (Test-Path $jar) { return }
    Write-Host "Downloading Lavalink.jar..."
    Set-Location $dir
    $release = Invoke-RestMethod "https://api.github.com/repos/lavalink-devs/Lavalink/releases/latest"
    $url = ($release.assets | Where-Object { $_.name -eq "Lavalink.jar" }).browser_download_url
    Invoke-WebRequest -Uri $url -OutFile "Lavalink.jar"
    $release.tag_name | Out-File "version.txt"
    Set-Location $Root
}

function Ensure-Postgres {
    param([string]$PgRoot, [string]$DataDir, [string]$User, [string]$Password, [string]$Db)

    if (-not (Test-Path (Join-Path $PgRoot "bin\initdb.exe"))) {
        Write-Host 'Downloading PostgreSQL 17 binaries - one-time download about 300 MB...'
        $zip = Join-Path $env:TEMP "postgresql-binaries.zip"
        Invoke-WebRequest -Uri "https://get.enterprisedb.com/postgresql/postgresql-17.5-1-windows-x64-binaries.zip" -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath (Join-Path $Root "data") -Force
        $extracted = Get-ChildItem (Join-Path $Root "data") -Directory | Where-Object { $_.Name -like "pgsql*" } | Select-Object -First 1
        if ($extracted) { $PgRoot = $extracted.FullName }
    }

    $initdb = (Join-Path $PgRoot "bin\initdb.exe")
    $pgctl = (Join-Path $PgRoot "bin\pg_ctl.exe")
    $psql = Join-Path $PgRoot "bin\psql.exe"
    $createdb = Join-Path $PgRoot "bin\createdb.exe"
    $createuser = Join-Path $PgRoot "bin\createuser.exe"

    if (-not (Test-Path $initdb)) {
        throw "PostgreSQL binaries not found under $PgRoot. Install PostgreSQL or Docker and use compose.yaml instead."
    }

    if (-not (Test-Path $DataDir)) {
        Write-Host "Initializing PostgreSQL data directory..."
        & "$initdb" -D $DataDir -U postgres -A trust -E UTF8
        $conf = Join-Path $DataDir "postgresql.conf"
        (Get-Content $conf) -replace "#listen_addresses = 'localhost'", "listen_addresses = 'localhost'" `
            -replace "#port = 5432", "port = 5432" | Set-Content $conf
    }

    $listening = Get-NetTCPConnection -LocalPort 5432 -State Listen -ErrorAction SilentlyContinue
    if (-not $listening) {
        Write-Host "Starting PostgreSQL..."
        Start-Process -FilePath $pgctl -ArgumentList @('-D', $DataDir, '-l', (Join-Path $DataDir 'server.log'), 'start', '-w') -Wait -NoNewWindow
    }

    Start-Sleep -Seconds 2
    $userExists = & "$psql" -U postgres -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$User'" 2>$null
    if ($userExists -ne "1") {
        & "$createuser" -U postgres -s $User
        & "$psql" -U postgres -c "ALTER USER $User WITH PASSWORD '$Password';"
    }
    $dbExists = & "$psql" -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$Db'" 2>$null
    if ($dbExists -ne "1") {
        & "$createdb" -U postgres -O $User $Db
    }
}

function Find-JavaExe {
    $java = Get-Command java -ErrorAction SilentlyContinue
    if ($java) { return $java.Source }
    $candidates = Get-ChildItem $env:LOCALAPPDATA -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "jdk*" } |
        ForEach-Object { Join-Path $_.FullName "bin\java.exe" } |
        Where-Object { Test-Path $_ }
    return $candidates | Select-Object -First 1
}

function Start-Lavalink {
    param([string]$LavalinkDir)
    $javaExe = Find-JavaExe
    if (-not $javaExe) {
        Write-Warning "Java 21+ not found. Install Temurin JDK 21, then re-run this script."
        Write-Warning "  https://adoptium.net/temurin/releases/?version=21"
        return $null
    }
    $proc = Start-Process -FilePath $javaExe -ArgumentList "-jar", "Lavalink.jar" `
        -WorkingDirectory $LavalinkDir -PassThru -WindowStyle Hidden
    Write-Host "Lavalink started (PID $($proc.Id))"
    return $proc
}

Import-VcVars
Add-ToolPaths
Ensure-EnvFile
Ensure-Lavalink

if ($BuildOnly) {
    cargo build --release
    exit $LASTEXITCODE
}

$pgRoot = Join-Path $Root "data\postgresql"
if (-not (Test-Path (Join-Path $pgRoot "bin\initdb.exe"))) {
    $altPg = Join-Path $Root "data\pgsql"
    if (Test-Path (Join-Path $altPg "bin\initdb.exe")) { $pgRoot = $altPg }
}
$dataDir = Join-Path $Root "data\pgdata"
Ensure-Postgres -PgRoot $pgRoot -DataDir $dataDir `
    -User $env:POSTGRES_USER -Password $env:POSTGRES_PASSWORD -Db $env:POSTGRES_DB

$lavalinkProc = Start-Lavalink -LavalinkDir (Join-Path $Root "lavalink")

if (-not (Test-Path "target\release\lyra.exe")) {
    Write-Host "Building lyra (release)..."
    cargo build --release
}

if ($NoRun) {
    Write-Host "Services ready. Run: cargo run --release"
    exit 0
}

if ($env:BOT_TOKEN -match 'REPLACE_WITH' -or [string]::IsNullOrWhiteSpace($env:BOT_TOKEN)) {
    Write-Warning "Set BOT_TOKEN in .env (.\scripts\set-bot-token.ps1), then run .\scripts\start-lyra.ps1"
    exit 1
}

& (Join-Path $PSScriptRoot "start-lyra.ps1")
