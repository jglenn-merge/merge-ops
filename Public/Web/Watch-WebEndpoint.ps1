function Watch-WebEndpoint {
    <#
    .SYNOPSIS
    Requests a URL repeatedly until it fails, to catch intermittent errors.

    .DESCRIPTION
    Sends requests in a loop and outputs a detail record for each failed request. The loop stops when -FailureLimit failures
    have been seen or -MaxRequests requests have been sent. Setting both to 0 runs until you press Ctrl+C.

    .PARAMETER Uri
    URL to request.

    .PARAMETER MaxRequests
    Stop after this many requests. 0 means no limit.

    .PARAMETER FailureLimit
    Stop after this many failures. 0 means no limit.

    .PARAMETER DelayMs
    Pause between requests.

    .PARAMETER Headers
    Extra request headers.

    .PARAMETER LogPath
    Optional file to append failure details to.

    .PARAMETER TimeoutSec
    Per-request timeout.

    .EXAMPLE
    Watch-WebEndpoint -Uri 'https://cd.example.com/-/media/icons/icon-time.svg' -LogPath .\request_errors.log

    .EXAMPLE
    Watch-WebEndpoint -Uri https://www.example.com -MaxRequests 1000 -FailureLimit 0 | Group-Object StatusCode
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxRequests = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$FailureLimit = 1,

        [ValidateRange(0, 600000)]
        [int]$DelayMs = 100,

        [hashtable]$Headers = @{},

        [string]$LogPath,

        [int]$TimeoutSec = 100
    )

    $hostName = ([uri]$Uri).Host
    $requestCount = 0
    $failureCount = 0

    while ($true) {
        $requestCount++
        Write-Progress -Activity "Watching $Uri" -Status "Request $requestCount, $failureCount failure(s)"
        $result = Invoke-TimedRequest -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec

        if (-not $result.Success) {
            $failureCount++
            try {
                $remoteIp = ([Net.Dns]::GetHostAddresses($hostName) | ForEach-Object { $_.IPAddressToString }) -join ', '
            }
            catch {
                $remoteIp = 'Could not resolve IP'
            }

            $failure = [pscustomobject]@{
                Timestamp     = $result.Timestamp
                RequestNumber = $requestCount
                Uri           = $Uri
                RemoteIP      = $remoteIp
                StatusCode    = $result.StatusCode
                ElapsedMs     = $result.ElapsedMs
                ExceptionType = $result.ExceptionType
                Error         = $result.Error
            }

            if ($LogPath) {
                $entry = @"
Time: $($failure.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))
Request Number: $($failure.RequestNumber)
URL: $($failure.Uri)
Remote IP: $($failure.RemoteIP)
Status Code: $($failure.StatusCode)
Exception: $($failure.ExceptionType)
Error Message: $($failure.Error)
------------------------------------------

"@
                Add-Content -LiteralPath $LogPath -Value $entry
            }
            $failure
        }

        if ($FailureLimit -gt 0 -and $failureCount -ge $FailureLimit) {
            break
        }
        if ($MaxRequests -gt 0 -and $requestCount -ge $MaxRequests) {
            break
        }
        if ($DelayMs -gt 0) {
            Start-Sleep -Milliseconds $DelayMs
        }
    }

    Write-Progress -Activity "Watching $Uri" -Completed
    Write-Verbose "Completed $requestCount request(s) with $failureCount failure(s)."
}
