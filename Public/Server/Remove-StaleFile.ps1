function Remove-StaleFile {
    <#
    .SYNOPSIS
    Deletes files older than a retention period.

    .DESCRIPTION
    Removes files whose LastWriteTime is older than -OlderThanDays and that match -Include and do not match -Exclude.
    Outputs each removed file. Supports -WhatIf, which is the recommended first run against any new path.

    .PARAMETER Path
    Folder to clean.

    .PARAMETER OlderThanDays
    Retention period in days.

    .PARAMETER Include
    File name patterns to consider.

    .PARAMETER Exclude
    File name patterns to always keep.

    .PARAMETER Recurse
    Include subfolders.

    .EXAMPLE
    Remove-StaleFile -Path E:\SQLBackup -OlderThanDays 5 -Include '*.bak', '*.trn' -WhatIf

    .EXAMPLE
    Remove-StaleFile -Path C:\inetpub\wwwroot\cm\temp\screenshots -OlderThanDays 0 -Include '*.jpg' -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 36500)]
        [int]$OlderThanDays,

        [string[]]$Include = @('*'),

        [string[]]$Exclude = @(),

        [switch]$Recurse
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Folder '$Path' does not exist."
    }

    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $files = Get-ChildItem -LiteralPath $Path -File -Recurse:$Recurse | Where-Object {
        $_.LastWriteTime -lt $cutoff -and
        (Test-WildcardMatch -Value $_.Name -Pattern $Include) -and
        -not (Test-WildcardMatch -Value $_.Name -Pattern $Exclude)
    }

    foreach ($file in $files) {
        if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove file')) {
            Remove-Item -LiteralPath $file.FullName -Force -Confirm:$false
            $file
        }
    }
}
