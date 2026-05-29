#Requires -Version 5.1
# Write BOT_TOKEN into .env (does not print the token).
param(
    [Parameter(Mandatory = $false)]
    [string]$Token
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$envFile = Join-Path $Root ".env"

if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $Root ".env.example") $envFile
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $secure = Read-Host "Paste your Discord bot token" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

$Token = $Token.Trim().Trim('"').Trim("'")
if ($Token -match 'REPLACE_WITH' -or [string]::IsNullOrWhiteSpace($Token)) {
    Write-Error "Token is empty or still a placeholder."
}
if ($Token -match '^\s*\{') {
    Write-Error "Paste only the bot token string, not JSON from browser storage."
}
try {
    $null = Invoke-RestMethod "https://discord.com/api/v10/users/@me" -Headers @{Authorization="Bot $Token"} -TimeoutSec 10
} catch {
    Write-Error @"
Discord rejected this as a bot token. Use Developer Portal → your app → Bot → Reset Token.
Do not use tokens from browser localStorage (those are often your user account token).
"@
}

$lines = Get-Content $envFile
$found = $false
$newLines = foreach ($line in $lines) {
    if ($line -match '^\s*BOT_TOKEN\s*=') {
        $found = $true
        "BOT_TOKEN=$Token"
    } else {
        $line
    }
}
if (-not $found) {
    $newLines = @("BOT_TOKEN=$Token") + $newLines
}
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($envFile, ($newLines -join "`n") + "`n", $utf8)
Write-Host "BOT_TOKEN saved in .env"
