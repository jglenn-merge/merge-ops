function Clear-SitecoreBinFolder {
    <#
    .SYNOPSIS
    Strips a Sitecore site's bin folder down to an allow list before a deploy.

    .DESCRIPTION
    Removes every file in <Path>\bin that does not match -Keep or -AdditionalKeep, then removes the folders listed in
    -RemoveDirectory. This clears out stale assemblies left over from earlier deploys so the package delivers a clean bin.
    Outputs each removed item.

    .PARAMETER Path
    Site root (the folder that contains bin). A path that already ends in bin is used as-is.

    .PARAMETER Keep
    File name patterns that are never removed.

    .PARAMETER AdditionalKeep
    Extra patterns to keep. Each entry may be a comma-separated list, which matches how Octopus variables are usually stored.

    .PARAMETER RemoveDirectory
    Subfolders of bin to delete.

    .EXAMPLE
    Clear-SitecoreBinFolder -Path C:\inetpub\wwwroot\cm.example.com -AdditionalKeep 'Sitecore.Kernel.*,Sitecore.Mvc.*' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$Keep = @('Merge*', 'Sitecore.Support*', 'Sitemap.XML*', 'SitecoreFriendlyErrors*'),

        [string[]]$AdditionalKeep = @(),

        [string[]]$RemoveDirectory = @('roslyn', 'de')
    )

    if ((Split-Path -Leaf $Path) -eq 'bin') {
        $binPath = $Path
    }
    else {
        $binPath = Join-Path $Path 'bin'
    }

    if (-not (Test-Path -LiteralPath $binPath -PathType Container)) {
        Write-Warning "No bin folder found at $binPath."
        return
    }

    $patterns = @($Keep) + @($AdditionalKeep | ForEach-Object { $_ -split ',' }) |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }

    foreach ($file in (Get-ChildItem -LiteralPath $binPath -File)) {
        if (Test-WildcardMatch -Value $file.Name -Pattern $patterns) {
            continue
        }
        if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove file')) {
            Remove-Item -LiteralPath $file.FullName -Force -Confirm:$false
            $file
        }
    }

    foreach ($directory in $RemoveDirectory) {
        $directoryPath = Join-Path $binPath $directory
        if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
            continue
        }
        if ($PSCmdlet.ShouldProcess($directoryPath, 'Remove folder')) {
            $item = Get-Item -LiteralPath $directoryPath
            Remove-Item -LiteralPath $directoryPath -Recurse -Force -Confirm:$false
            $item
        }
    }
}
