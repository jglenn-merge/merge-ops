function Get-LatencyStatistic {
    [CmdletBinding()]
    param(
        [double[]]$Value
    )

    if (-not $Value -or $Value.Count -eq 0) {
        return [pscustomobject]@{ Average = $null; Median = $null; Min = $null; Max = $null }
    }

    $sorted = @($Value | Sort-Object)
    $middle = [int][math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) {
        $median = $sorted[$middle]
    }
    else {
        $median = ($sorted[$middle - 1] + $sorted[$middle]) / 2
    }

    $measure = $Value | Measure-Object -Average -Minimum -Maximum
    [pscustomobject]@{
        Average = [math]::Round($measure.Average, 1)
        Median  = [math]::Round($median, 1)
        Min     = [math]::Round($measure.Minimum, 1)
        Max     = [math]::Round($measure.Maximum, 1)
    }
}
