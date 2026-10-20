function New-ReleaseFolder {
    <#
    .SYNOPSIS
    Creates a versioned release folder, optionally seeded with a copy of the previous release.

    .DESCRIPTION
    Creates <DeploymentRoot>\<Release>. With -CopyPrevious, the newest existing release folder (by creation time) is copied
    into it with robocopy, skipping Sitecore diagnostics, logs, media cache, and viewstate folders by default. If the release
    folder already exists, a warning is written and the existing folder is returned unchanged, so a redeploy of the same
    release does not fail.

    Robocopy exit codes below 8 indicate success. The function resets $LASTEXITCODE to 0 in that case, because Octopus fails a
    PowerShell step that ends with a non-zero $LASTEXITCODE.

    .PARAMETER DeploymentRoot
    Folder that holds one subfolder per release.

    .PARAMETER Release
    Name of the new release folder, usually the release number.

    .PARAMETER CopyPrevious
    Copy the newest existing release into the new folder.

    .PARAMETER ExcludeDirectory
    Paths relative to the previous release folder that are not copied.

    .EXAMPLE
    New-ReleaseFolder -DeploymentRoot D:\sites\cm -Release $OctopusParameters['Octopus.Release.Number'] -CopyPrevious
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeploymentRoot,

        [Parameter(Mandatory = $true)]
        [string]$Release,

        [switch]$CopyPrevious,

        [string[]]$ExcludeDirectory = @(
            'App_Data\diagnostics\configuration_history'
            'App_Data\diagnostics\health_monitor'
            'App_Data\diagnostics\counters'
            'App_Data\logs'
            'App_Data\MediaCache'
            'App_Data\viewstate'
        )
    )

    if (-not (Test-Path -LiteralPath $DeploymentRoot -PathType Container)) {
        throw "Deployment root '$DeploymentRoot' does not exist."
    }

    $root = (Resolve-Path -LiteralPath $DeploymentRoot).ProviderPath
    $releasePath = Join-Path $root $Release

    if (Test-Path -LiteralPath $releasePath) {
        Write-Warning "Release folder '$releasePath' already exists. Skipping creation."
        return Get-Item -LiteralPath $releasePath
    }

    # Find the previous release before creating the new folder, which would otherwise be the newest.
    $previous = Get-ChildFolderByAge -Path $root | Select-Object -First 1

    if (-not $PSCmdlet.ShouldProcess($releasePath, 'Create release folder')) {
        return
    }
    $folder = New-Item -ItemType Directory -Path $releasePath

    if ($CopyPrevious) {
        if (-not $previous -or -not (Get-ChildItem -LiteralPath $previous.FullName | Select-Object -First 1)) {
            Write-Warning "No previous release with content was found under $root. Nothing to copy."
        }
        else {
            Write-Verbose "Copying $($previous.FullName) to $($folder.FullName)"
            $arguments = @($previous.FullName, $folder.FullName, '/E', '/NDL', '/NJH', '/NJS', '/NP', '/NS', '/NC', '/NFL')
            if ($ExcludeDirectory) {
                $arguments += '/XD'
                $arguments += @($ExcludeDirectory | ForEach-Object { Join-Path $previous.FullName $_ })
            }

            & robocopy.exe @arguments | ForEach-Object { Write-Verbose $_ }
            $exitCode = $LASTEXITCODE
            if ($exitCode -ge 8) {
                throw "robocopy failed with exit code $exitCode."
            }
            $global:LASTEXITCODE = 0
        }
    }

    $folder
}
