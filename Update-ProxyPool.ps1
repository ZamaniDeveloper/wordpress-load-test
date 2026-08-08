[CmdletBinding()]
param(
    [string[]]$SourceUrls = @(
        "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/http/data.txt",
        "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/https/data.txt",
        "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt"
    ),
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TestUrl,
    [ValidateRange(1, 500)]
    [int]$MaxCandidates = 30,
    [ValidateRange(1, 50)]
    [int]$MaxWorking = 5,
    [ValidateRange(1, 30)]
    [int]$TimeoutSeconds = 5,
    [ValidateRange(1, 50)]
    [int]$ThrottleLimit = 10,
    [string]$OutputFile = (Join-Path $PSScriptRoot ".proxy-cache\working-proxies.txt")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

function Test-PublicIPv4 {
    param([Parameter(Mandatory = $true)][string]$Address)

    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) {
        return $false
    }

    if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }

    $bytes = $parsed.GetAddressBytes()

    if ($bytes[0] -in @(0, 10, 127)) { return $false }
    if ($bytes[0] -ge 224) { return $false }
    if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return $false }
    if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return $false }
    if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { return $false }
    if ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) { return $false }
    if ($bytes[0] -eq 198 -and $bytes[1] -in @(18, 19)) { return $false }

    return $true
}

function ConvertTo-HttpProxyUri {
    param([Parameter(Mandatory = $true)][string]$Value)

    $candidate = $Value.Trim()
    $pattern = '^(?:(?:http|https)://)?(?<host>(?:\d{1,3}\.){3}\d{1,3}):(?<port>\d{1,5})/?$'

    if ($candidate -notmatch $pattern) {
        return $null
    }

    $hostAddress = $Matches.host
    $port = [int]$Matches.port

    if (-not (Test-PublicIPv4 -Address $hostAddress) -or $port -lt 1 -or $port -gt 65535) {
        return $null
    }

    # HTTP_PROXY/HTTPS_PROXY expect the forward-proxy URI. HTTPS-capable
    # entries commonly still use http:// and tunnel TLS via CONNECT.
    return "http://${hostAddress}:$port"
}

function Test-Proxy {
    param(
        [Parameter(Mandatory = $true)][string]$ProxyUrl,
        [Parameter(Mandatory = $true)][uri]$Destination,
        [Parameter(Mandatory = $true)][int]$Timeout
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $true
    $handler.Proxy = [System.Net.WebProxy]::new($ProxyUrl)
    $handler.AllowAutoRedirect = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($Timeout)
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Destination)
    $request.Headers.UserAgent.ParseAdd("wordpress-load-test-proxy-check/1.0")
    $startedAt = [DateTime]::UtcNow

    try {
        $response = $client.SendAsync(
            $request,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()

        $statusCode = [int]$response.StatusCode
        $elapsedMs = [int]([DateTime]::UtcNow - $startedAt).TotalMilliseconds
        $response.Dispose()

        if ($statusCode -ge 200 -and $statusCode -lt 500 -and $statusCode -ne 407) {
            return [PSCustomObject]@{
                Proxy = $ProxyUrl
                StatusCode = $statusCode
                LatencyMs = $elapsedMs
            }
        }
    }
    catch {
        return $null
    }
    finally {
        $request.Dispose()
        $client.Dispose()
        $handler.Dispose()
    }

    return $null
}

$testUri = $null
if (-not [uri]::TryCreate($TestUrl, [UriKind]::Absolute, [ref]$testUri) -or
    $testUri.Scheme -notin @("http", "https")) {
    throw "TestUrl must be an absolute HTTP or HTTPS URL."
}

$candidates = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

foreach ($sourceUrl in $SourceUrls) {
    $sourceUri = $null
    if (-not [uri]::TryCreate($sourceUrl, [UriKind]::Absolute, [ref]$sourceUri) -or
        $sourceUri.Scheme -ne "https" -or
        $sourceUri.Host -ne "raw.githubusercontent.com") {
        Write-Warning "Skipping non-GitHub or non-HTTPS proxy source: $sourceUrl"
        continue
    }

    try {
        Write-Host "Downloading proxy candidates from $sourceUrl"
        $response = Invoke-WebRequest -Uri $sourceUri -UseBasicParsing -TimeoutSec 20
        $content = [string]$response.Content

        if ($content.Length -gt 10MB) {
            Write-Warning "Skipping source larger than 10 MB: $sourceUrl"
            continue
        }

        foreach ($line in ($content -split "`r?`n")) {
            $proxyUrl = ConvertTo-HttpProxyUri -Value $line
            if ($proxyUrl) {
                [void]$candidates.Add($proxyUrl)
            }
        }
    }
    catch {
        Write-Warning "Could not download proxy source $sourceUrl`: $($_.Exception.Message)"
    }
}

if ($candidates.Count -eq 0) {
    throw "No valid public HTTP proxy candidates were downloaded from the configured GitHub sources."
}

$sampleSize = [Math]::Min($MaxCandidates, $candidates.Count)
$sample = @($candidates | Get-Random -Count $sampleSize)
Write-Host "Testing $sampleSize proxy candidates against $($testUri.GetLeftPart([UriPartial]::Authority))"

$working = if ($PSVersionTable.PSVersion.Major -ge 7) {
    @($sample | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $proxyUrl = $_
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.UseProxy = $true
        $handler.Proxy = [System.Net.WebProxy]::new($proxyUrl)
        $handler.AllowAutoRedirect = $false
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($using:TimeoutSeconds)
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Get,
            $using:testUri.AbsoluteUri
        )
        $request.Headers.UserAgent.ParseAdd("wordpress-load-test-proxy-check/1.0")
        $startedAt = [DateTime]::UtcNow

        try {
            $response = $client.SendAsync(
                $request,
                [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
            ).GetAwaiter().GetResult()
            $statusCode = [int]$response.StatusCode
            $elapsedMs = [int]([DateTime]::UtcNow - $startedAt).TotalMilliseconds
            $response.Dispose()

            if ($statusCode -ge 200 -and $statusCode -lt 500 -and $statusCode -ne 407) {
                [PSCustomObject]@{
                    Proxy = $proxyUrl
                    StatusCode = $statusCode
                    LatencyMs = $elapsedMs
                }
            }
        }
        catch {
            # An unavailable public proxy is expected and is omitted.
        }
        finally {
            $request.Dispose()
            $client.Dispose()
            $handler.Dispose()
        }
    })
}
else {
    $sequentialResults = [System.Collections.Generic.List[object]]::new()
    foreach ($proxyUrl in $sample) {
        $result = Test-Proxy -ProxyUrl $proxyUrl -Destination $testUri -Timeout $TimeoutSeconds
        if ($result) {
            $sequentialResults.Add($result)
        }
    }
    @($sequentialResults)
}

if ($working.Count -eq 0) {
    throw "No working proxy was found. Increase MAX_PROXY_CANDIDATES or try again later."
}

$outputDirectory = Split-Path -Parent $OutputFile
if ($outputDirectory) {
    [void](New-Item -ItemType Directory -Force -Path $outputDirectory)
}

$sorted = @($working | Sort-Object LatencyMs | Select-Object -First $MaxWorking)
foreach ($result in $sorted) {
    Write-Host "Working proxy: $($result.Proxy) ($($result.LatencyMs) ms)"
}
$sorted.Proxy | Set-Content -LiteralPath $OutputFile -Encoding ascii
Write-Host "Saved $($sorted.Count) working proxies to $OutputFile"

$sorted
