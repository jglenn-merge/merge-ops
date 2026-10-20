function Compress-ReleaseFolder {
    <#
    .SYNOPSIS
    Zips all but the newest release folders into an archive folder.

    .DESCRIPTION
    Keeps the newest -Keep folders (by creation time) under -Path and zips the rest into -ArchivePath, one zip per folder.
    With -RemoveAfterArchive, each folder is deleted after its zip is written. Existing zips are never overwritten.
    Uses System.IO.Compression directly, which avoids the 2 GB limit of Compress-Archive in Windows PowerShell.

    .PARAMETER Path
    Folder that holds one subfolder per release.

    .PARAMETER ArchivePath
    Folder to write zip files to. Created if it does not exist.

    .PARAMETER Keep
    Number of newest release folders to leave alone.

    .PARAMETER RemoveAfterArchive
    Delete each release folder after it is archived.

    .EXAMPLE
    Compress-ReleaseFolder -Path D:\sites\cm -ArchivePath E:\archive\cm -Keep 3 -RemoveAfterArchive -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [ValidateRange(0, 1000)]
        [int]$Keep = 2,

        [switch]$RemoveAfterArchive
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Folder '$Path' does not exist."
    }

    $archiveRoot = (Resolve-FullPath -Path $ArchivePath).TrimEnd('\')
    $folders = @(Get-ChildFolderByAge -Path $Path | Where-Object { $_.FullName.TrimEnd('\') -ne $archiveRoot } | Select-Object -Skip $Keep)
    if ($folders.Count -eq 0) {
        Write-Verbose "Nothing to archive. $Path has $Keep or fewer release folders."
        return
    }

    if (-not (Test-Path -LiteralPath $archiveRoot)) {
        New-Item -ItemType Directory -Path $archiveRoot | Out-Null
    }

    foreach ($folder in $folders) {
        $zipPath = Join-Path $archiveRoot "$($folder.Name).zip"
        if (Test-Path -LiteralPath $zipPath) {
            Write-Warning "Archive '$zipPath' already exists. Skipping $($folder.FullName)."
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($folder.FullName, "Archive to $zipPath")) {
            continue
        }

        try {
            [IO.Compression.ZipFile]::CreateFromDirectory($folder.FullName, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $true)
        }
        catch {
            Write-Error "Failed to archive $($folder.FullName): $($_.Exception.Message)"
            continue
        }

        $removed = $false
        if ($RemoveAfterArchive -and $PSCmdlet.ShouldProcess($folder.FullName, 'Remove folder')) {
            Remove-Item -LiteralPath $folder.FullName -Recurse -Force -Confirm:$false
            $removed = $true
        }

        [pscustomobject]@{
            Folder      = $folder.FullName
            ArchivePath = $zipPath
            Removed     = $removed
        }
    }
}
