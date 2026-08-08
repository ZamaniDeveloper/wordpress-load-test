$ErrorActionPreference = "Stop"

$envFile = Join-Path $PSScriptRoot ".env"

if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }

        $parts = $line.Split("=", 2)
        if ($parts.Count -ne 2) { return }

        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($key -match '^[A-Za-z_][A-Za-z0-9_]*$') {
            Set-Item -Path "Env:$key" -Value $value
        }
    }
}

$k6Command = Get-Command k6 -ErrorAction SilentlyContinue
$k6Exe = if ($k6Command) { $k6Command.Source } else { "C:\Program Files\k6\k6.exe" }

if (-not (Test-Path $k6Exe)) {
    Write-Host "k6 is not installed or not available in PATH."
    Write-Host "Install it with: winget install k6 --source winget"
    exit 1
}

$env:TARGET_URL = if ($env:TARGET_URL) { $env:TARGET_URL } else { "https://example.com" }
$env:MODE = if ($env:MODE) { $env:MODE } else { "vus" }
$env:VUS = if ($env:VUS) { $env:VUS } else { "10" }
$env:RAMP_UP = if ($env:RAMP_UP) { $env:RAMP_UP } else { "1m" }
$env:HOLD = if ($env:HOLD) { $env:HOLD } else { "3m" }
$env:RAMP_DOWN = if ($env:RAMP_DOWN) { $env:RAMP_DOWN } else { "1m" }
$env:SLEEP = if ($env:SLEEP) { $env:SLEEP } else { "1" }
$env:PATHS = if ($env:PATHS) { $env:PATHS } else { "/" }

$useProxy = $env:USE_PROXY -and $env:USE_PROXY.Trim().ToLowerInvariant() -in @("1", "true", "yes", "on")

if ($useProxy) {
    $proxyCacheFile = Join-Path $PSScriptRoot ".proxy-cache\working-proxies.txt"
    $cacheMinutes = if ($env:PROXY_CACHE_MINUTES) { [int]$env:PROXY_CACHE_MINUTES } else { 60 }
    $cacheIsFresh = (Test-Path $proxyCacheFile) -and
        (Get-Item $proxyCacheFile).Length -gt 0 -and
        ((Get-Date) - (Get-Item $proxyCacheFile).LastWriteTime).TotalMinutes -lt $cacheMinutes

    if (-not $cacheIsFresh) {
        $providerFile = if ($env:PROXY_PROVIDERS_FILE) {
            if ([IO.Path]::IsPathRooted($env:PROXY_PROVIDERS_FILE)) {
                $env:PROXY_PROVIDERS_FILE
            }
            else {
                Join-Path $PSScriptRoot $env:PROXY_PROVIDERS_FILE
            }
        }
        else {
            Join-Path $PSScriptRoot "proxy-providers.json"
        }

        $proxyParams = @{
            ProviderFile = $providerFile
            TestUrl = if ($env:PROXY_TEST_URL) { $env:PROXY_TEST_URL } else { $env:TARGET_URL }
            MaxCandidates = if ($env:MAX_PROXY_CANDIDATES) { [int]$env:MAX_PROXY_CANDIDATES } else { 30 }
            MaxWorking = if ($env:MAX_WORKING_PROXIES) { [int]$env:MAX_WORKING_PROXIES } else { 5 }
            ThrottleLimit = if ($env:PROXY_TEST_CONCURRENCY) { [int]$env:PROXY_TEST_CONCURRENCY } else { 10 }
            OutputFile = $proxyCacheFile
        }

        & "$PSScriptRoot\Update-ProxyPool.ps1" @proxyParams | Out-Null
    }

    $workingProxies = @(Get-Content -LiteralPath $proxyCacheFile | Where-Object {
        $_ -match '^(http|socks5)://'
    })
    if ($workingProxies.Count -eq 0) {
        throw "No k6-compatible HTTP or SOCKS5 proxy is available. SOCKS4 is validated but cannot be selected by k6."
    }

    $selectedProxy = $workingProxies | Get-Random
    $env:HTTP_PROXY = $selectedProxy
    $env:HTTPS_PROXY = $selectedProxy
    $env:http_proxy = $selectedProxy
    $env:https_proxy = $selectedProxy
    $env:NO_PROXY = ""
    $env:no_proxy = ""
    Write-Host "Using proxy for this k6 run: $selectedProxy"
}

& $k6Exe run "$PSScriptRoot\site-load-test.js"
exit $LASTEXITCODE
