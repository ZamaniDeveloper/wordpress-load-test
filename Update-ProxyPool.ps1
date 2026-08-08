[CmdletBinding()]
param(
    [string]$ProviderFile,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TestUrl,
    [ValidateRange(1, 500)]
    [int]$MaxCandidates = 30,
    [ValidateRange(1, 100)]
    [int]$MaxWorking = 10,
    [ValidateRange(1, 50)]
    [int]$ThrottleLimit = 10,
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"

if (-not $ProviderFile) {
    $ProviderFile = Join-Path $PSScriptRoot "proxy-providers.json"
}
if (-not $OutputFile) {
    $OutputFile = Join-Path $PSScriptRoot ".proxy-cache\working-proxies.txt"
}

function Test-PublicIPv4 {
    param([Parameter(Mandatory = $true)][string]$Address)

    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed) -or
        $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }

    $bytes = $parsed.GetAddressBytes()
    if ($bytes[0] -in @(0, 10, 127)) { return $false }
    if ($bytes[0] -ge 224) { return $false }
    if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return $false }
    if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return $false }
    if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { return $false }
    if ($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and $bytes[2] -in @(0, 2)) { return $false }
    if ($bytes[0] -eq 192 -and $bytes[1] -eq 88 -and $bytes[2] -eq 99) { return $false }
    if ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) { return $false }
    if ($bytes[0] -eq 198 -and $bytes[1] -in @(18, 19)) { return $false }
    if ($bytes[0] -eq 198 -and $bytes[1] -eq 51 -and $bytes[2] -eq 100) { return $false }
    if ($bytes[0] -eq 203 -and $bytes[1] -eq 0 -and $bytes[2] -eq 113) { return $false }
    return $true
}

function ConvertTo-ProxyCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][ValidateSet(1, 4, 5)][int]$Type,
        [Parameter(Mandatory = $true)][int]$Timeout
    )

    $candidate = $Value.Trim()
    $pattern = '^(?:(?:http|https|socks4|socks5)://)?(?<host>(?:\d{1,3}\.){3}\d{1,3}):(?<port>\d{1,5})/?$'
    if ($candidate -notmatch $pattern) { return $null }

    $hostAddress = $Matches.host
    $port = [int]$Matches.port
    if (-not (Test-PublicIPv4 -Address $hostAddress) -or $port -lt 1 -or $port -gt 65535) {
        return $null
    }

    $scheme = switch ($Type) {
        1 { "http" }
        4 { "socks4" }
        5 { "socks5" }
    }

    [PSCustomObject]@{
        Key = "$Type|${hostAddress}:$port"
        Type = $Type
        Proxy = "${scheme}://${hostAddress}:$port"
        CurlProxy = if ($Type -eq 5) { "socks5h://${hostAddress}:$port" } else { "${scheme}://${hostAddress}:$port" }
        Timeout = $Timeout
    }
}

function Test-ProxyWithCurl {
    param(
        [Parameter(Mandatory = $true)][object]$Candidate,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$CurlPath,
        [Parameter(Mandatory = $true)][string]$NullDevice
    )

    $startedAt = [DateTime]::UtcNow
    # Proxy failures and timeouts are expected. Keep curl silent and use its
    # exit code so Windows PowerShell does not turn stderr into NativeCommandError.
    $statusText = & $CurlPath --silent --output $NullDevice `
        --write-out "%{http_code}" --max-time $Candidate.Timeout `
        --proxy $Candidate.CurlProxy $Destination 2>$null
    $exitCode = $LASTEXITCODE
    $elapsedMs = [int]([DateTime]::UtcNow - $startedAt).TotalMilliseconds

    if ($exitCode -eq 0 -and $statusText -match '^\d{3}$') {
        $statusCode = [int]$statusText
        if ($statusCode -ge 200 -and $statusCode -lt 400) {
            return [PSCustomObject]@{
                Type = $Candidate.Type
                Proxy = $Candidate.Proxy
                StatusCode = $statusCode
                LatencyMs = $elapsedMs
            }
        }
    }

    return $null
}

$testUri = $null
if (-not [uri]::TryCreate($TestUrl, [UriKind]::Absolute, [ref]$testUri) -or
    $testUri.Scheme -notin @("http", "https")) {
    throw "TestUrl must be an absolute HTTP or HTTPS URL."
}

if (-not (Test-Path -LiteralPath $ProviderFile)) {
    throw "Proxy provider file not found: $ProviderFile"
}

$curlCommand = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $curlCommand) { $curlCommand = Get-Command curl -ErrorAction SilentlyContinue }
if (-not $curlCommand) {
    throw "curl is required for HTTP, SOCKS4, and SOCKS5 proxy validation."
}
$curlPath = $curlCommand.Source
$nullDevice = if ($IsWindows -or $PSVersionTable.PSEdition -eq "Desktop") { "NUL" } else { "/dev/null" }

$config = Get-Content -Raw -LiteralPath $ProviderFile | ConvertFrom-Json
$providers = @($config.'proxy-providers')
if ($providers.Count -eq 0) {
    throw "The provider file must contain a non-empty proxy-providers array."
}

$candidateMap = @{}
foreach ($provider in $providers) {
    $type = [int]$provider.type
    if ($type -notin @(1, 4, 5)) {
        Write-Warning "Skipping provider with unsupported type '$type'. Supported types: 1=HTTP, 4=SOCKS4, 5=SOCKS5."
        continue
    }

    $sourceUri = $null
    $sourceUrl = [string]$provider.url
    if (-not [uri]::TryCreate($sourceUrl, [UriKind]::Absolute, [ref]$sourceUri) -or
        $sourceUri.Scheme -ne "https" -or $sourceUri.Host -ne "raw.githubusercontent.com") {
        Write-Warning "Skipping non-GitHub or non-HTTPS provider: $sourceUrl"
        continue
    }

    $timeout = if ($provider.timeout) { [int]$provider.timeout } else { 5 }
    if ($timeout -lt 1 -or $timeout -gt 30) {
        Write-Warning "Skipping provider with timeout outside 1..30 seconds: $sourceUrl"
        continue
    }

    try {
        Write-Host "Downloading type $type proxies from $sourceUrl"
        $response = Invoke-WebRequest -Uri $sourceUri -UseBasicParsing -TimeoutSec 20
        $content = [string]$response.Content
        if ($content.Length -gt 10MB) {
            Write-Warning "Skipping source larger than 10 MB: $sourceUrl"
            continue
        }

        foreach ($line in ($content -split "`r?`n")) {
            $candidate = ConvertTo-ProxyCandidate -Value $line -Type $type -Timeout $timeout
            if ($candidate -and -not $candidateMap.ContainsKey($candidate.Key)) {
                $candidateMap[$candidate.Key] = $candidate
            }
        }
    }
    catch {
        Write-Warning "Could not download provider $sourceUrl`: $($_.Exception.Message)"
    }
}

if ($candidateMap.Count -eq 0) {
    throw "No valid public proxy candidates were downloaded from the configured GitHub providers."
}

$sampleSize = [Math]::Min($MaxCandidates, $candidateMap.Count)
$sample = @($candidateMap.Values | Get-Random -Count $sampleSize)
Write-Host "Testing $sampleSize mixed proxy candidates against $($testUri.GetLeftPart([UriPartial]::Authority))"

$working = if ($PSVersionTable.PSVersion.Major -ge 7) {
    @($sample | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $candidate = $_
        $startedAt = [DateTime]::UtcNow
        $statusText = & $using:curlPath --silent --output $using:nullDevice `
            --write-out "%{http_code}" --max-time $candidate.Timeout `
            --proxy $candidate.CurlProxy $using:testUri.AbsoluteUri 2>$null
        $exitCode = $LASTEXITCODE
        $elapsedMs = [int]([DateTime]::UtcNow - $startedAt).TotalMilliseconds

        if ($exitCode -eq 0 -and $statusText -match '^\d{3}$') {
            $statusCode = [int]$statusText
            if ($statusCode -ge 200 -and $statusCode -lt 400) {
                [PSCustomObject]@{
                    Type = $candidate.Type
                    Proxy = $candidate.Proxy
                    StatusCode = $statusCode
                    LatencyMs = $elapsedMs
                }
            }
        }
    })
}
else {
    @($sample | ForEach-Object {
        Test-ProxyWithCurl -Candidate $_ -Destination $testUri.AbsoluteUri -CurlPath $curlPath -NullDevice $nullDevice
    } | Where-Object { $_ })
}

if ($working.Count -eq 0) {
    throw "No working proxy was found. Increase MAX_PROXY_CANDIDATES or try again later."
}

$sorted = @(
    $working | Group-Object Type | ForEach-Object {
        $_.Group | Sort-Object LatencyMs | Select-Object -First $MaxWorking
    } | Sort-Object Type, LatencyMs
)
foreach ($result in $sorted) {
    Write-Host "Working type $($result.Type) proxy: $($result.Proxy) ($($result.LatencyMs) ms)"
}

$outputDirectory = Split-Path -Parent $OutputFile
if ($outputDirectory) { [void](New-Item -ItemType Directory -Force -Path $outputDirectory) }
$sorted.Proxy | Set-Content -LiteralPath $OutputFile -Encoding ascii
Write-Host "Saved $($sorted.Count) working proxies to $OutputFile"
$sorted
