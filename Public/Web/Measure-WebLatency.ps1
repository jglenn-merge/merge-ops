function Measure-WebLatency {
    <#
    .SYNOPSIS
    Measures response times for one or more URLs over repeated requests.

    .DESCRIPTION
    Requests each URL -Count times and reports average, median, minimum, and maximum response time. When several URLs are
    given, requests are interleaved (A, B, A, B) so a temporary slowdown affects every URL equally. This makes it suitable
    for comparing environments, such as dev against prod, or a JSS layout service call against the rendered page.

    Failed requests are counted but excluded from the timing figures.

    .PARAMETER Uri
    One or more URLs to measure. Accepts pipeline input.

    .PARAMETER Count
    Number of requests per URL.

    .PARAMETER Headers
    Extra request headers, such as an API key header.

    .PARAMETER DelayMs
    Pause between requests.

    .PARAMETER PassThru
    Output every individual request instead of the per-URL summary.

    .EXAMPLE
    Measure-WebLatency -Uri https://dev.example.com/medical-services, https://www.example.com/medical-services -Count 10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Uri,

        [ValidateRange(1, 10000)]
        [int]$Count = 10,

        [hashtable]$Headers = @{},

        [ValidateRange(0, 600000)]
        [int]$DelayMs = 0,

        [switch]$PassThru
    )

    begin {
        $targets = New-Object System.Collections.Generic.List[string]
    }

    process {
        foreach ($item in $Uri) {
            $targets.Add($item)
        }
    }

    end {
        $samples = New-Object System.Collections.Generic.List[object]
        $total = $Count * $targets.Count
        for ($i = 1; $i -le $Count; $i++) {
            foreach ($target in $targets) {
                Write-Progress -Activity 'Measuring latency' -Status "Pass $i of ${Count}: $target" -PercentComplete (($samples.Count / $total) * 100)
                $result = Invoke-TimedRequest -Uri $target -Headers $Headers
                $result | Add-Member -NotePropertyName Iteration -NotePropertyValue $i
                $samples.Add($result)

                if ($DelayMs -gt 0) {
                    Start-Sleep -Milliseconds $DelayMs
                }
            }
        }
        Write-Progress -Activity 'Measuring latency' -Completed

        if ($PassThru) {
            return $samples | Select-Object Iteration, Uri, Success, StatusCode, ElapsedMs, Error
        }

        foreach ($target in ($targets | Select-Object -Unique)) {
            $set = @($samples | Where-Object { $_.Uri -eq $target })
            $succeeded = @($set | Where-Object { $_.Success })
            $stats = Get-LatencyStatistic -Value @($succeeded | ForEach-Object { $_.ElapsedMs })

            [pscustomobject]@{
                Uri       = $target
                Requests  = $set.Count
                Failures  = $set.Count - $succeeded.Count
                AverageMs = $stats.Average
                MedianMs  = $stats.Median
                MinMs     = $stats.Min
                MaxMs     = $stats.Max
            }
        }
    }
}
