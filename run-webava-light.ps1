$ErrorActionPreference = "Stop"

$envFile = Join-Path $PSScriptRoot ".env"

if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()

        if (-not $line -or $line.StartsWith("#")) {
            return
        }

        $parts = $line.Split("=", 2)
        if ($parts.Count -ne 2) {
            return
        }

        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")

        if ($key) {
            Set-Item -Path "Env:$key" -Value $value
        }
    }
}

$k6Command = Get-Command k6 -ErrorAction SilentlyContinue
$k6Exe = if ($k6Command) { $k6Command.Source } else { "C:\Program Files\k6\k6.exe" }

if (-not (Test-Path $k6Exe)) {
    Write-Host "k6 is not installed or not available in PATH."
    Write-Host "Install it with: winget install GrafanaLabs.k6 --source winget"
    exit 1
}

$env:TARGET_URL = if ($env:TARGET_URL) { $env:TARGET_URL } else { "https://example.com" }
$env:VUS = if ($env:VUS) { $env:VUS } else { "10" }
$env:RAMP_UP = if ($env:RAMP_UP) { $env:RAMP_UP } else { "1m" }
$env:HOLD = if ($env:HOLD) { $env:HOLD } else { "3m" }
$env:RAMP_DOWN = if ($env:RAMP_DOWN) { $env:RAMP_DOWN } else { "1m" }
$env:SLEEP = if ($env:SLEEP) { $env:SLEEP } else { "1" }
$env:PATHS = if ($env:PATHS) { $env:PATHS } else { "/,/blog/,/?s=wordpress,/wp-json/" }

& $k6Exe run "$PSScriptRoot\wordpress-pressure.js"
