function Test-WebLoadBalancing {
    <#
    .SYNOPSIS
    Shows how a load balancer distributes requests by reading a backend identifier header from each response.

    .DESCRIPTION
    Sends -Count requests to a URL and groups the responses by the value of -HeaderName, which should be a header that each
    backend node sets to its own name. The summary shows how many requests each node served and their average response time.

    Use -DisableKeepAlive when testing a layer 4 load balancer. Otherwise the client reuses one TCP connection and every
    request lands on the same node.

    .PARAMETER Uri
    URL to request.

    .PARAMETER HeaderName
    Response header that identifies the backend node.

    .PARAMETER Count
    Number of requests to send.

    .PARAMETER Headers
    Extra request headers.

    .PARAMETER DelayMs
    Pause between requests.

    .PARAMETER DisableKeepAlive
    Open a new connection for each request.

    .PARAMETER PassThru
    Output every individual request instead of the per-node summary.

    .EXAMPLE
    Test-WebLoadBalancing -Uri https://www.example.com -HeaderName X-Current-Instance -Count 50 -DisableKeepAlive
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [string]$HeaderName = 'X-Current-Instance',

        [ValidateRange(1, 100000)]
        [int]$Count = 50,

        [hashtable]$Headers = @{},

        [ValidateRange(0, 600000)]
        [int]$DelayMs = 0,

        [switch]$DisableKeepAlive,

        [switch]$PassThru
    )

    $samples = for ($i = 1; $i -le $Count; $i++) {
        Write-Progress -Activity 'Testing load balancing' -Status "Request $i of $Count" -PercentComplete (($i / $Count) * 100)
        $result = Invoke-TimedRequest -Uri $Uri -Headers $Headers -DisableKeepAlive:$DisableKeepAlive

        if (-not $result.Success) {
            $instance = '(request failed)'
        }
        else {
            $instance = Get-HeaderValue -Headers $result.Headers -Name $HeaderName
            if (-not $instance) {
                $instance = '(header missing)'
            }
        }

        [pscustomobject]@{
            Request    = $i
            Instance   = $instance
            StatusCode = $result.StatusCode
            ElapsedMs  = $result.ElapsedMs
            Error      = $result.Error
        }

        if ($DelayMs -gt 0) {
            Start-Sleep -Milliseconds $DelayMs
        }
    }
    Write-Progress -Activity 'Testing load balancing' -Completed

    if ($PassThru) {
        return $samples
    }

    foreach ($group in ($samples | Group-Object -Property Instance | Sort-Object -Property Count -Descending)) {
        $stats = Get-LatencyStatistic -Value @($group.Group | ForEach-Object { $_.ElapsedMs })
        [pscustomobject]@{
            Instance  = $group.Name
            Requests  = $group.Count
            Percent   = [math]::Round(100 * $group.Count / $Count, 1)
            AverageMs = $stats.Average
        }
    }
}
