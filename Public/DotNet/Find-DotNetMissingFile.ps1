function Find-DotNetMissingFile {
    <#
    .SYNOPSIS
    Lists files referenced by a project that do not exist on disk.

    .DESCRIPTION
    Reads every item with an Include attribute in a .csproj, .vbproj, or .fsproj and reports the ones whose path does not
    exist. Passing a .sln checks every project in the solution. Works for both legacy and SDK-style projects.

    Assembly and package references are skipped because their Include is a name, not a path. Includes with wildcards or MSBuild
    properties ($(...)) are skipped because they cannot be checked without evaluating the project.

    .PARAMETER Path
    Project or solution files. FileInfo objects can be piped in.

    .PARAMETER IgnoreItemType
    Item types whose Include is not a file path.

    .EXAMPLE
    Find-DotNetMissingFile -Path .\Website.sln

    .EXAMPLE
    Get-ChildItem -Recurse -Filter *.vbproj | Find-DotNetMissingFile
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [string[]]$IgnoreItemType = @(
            'Reference', 'PackageReference', 'COMReference', 'BootstrapperPackage', 'Service',
            'WCFMetadataStorage', 'DotNetCliToolReference', 'FrameworkReference', 'Using'
        )
    )

    process {
        foreach ($project in (Resolve-ProjectFile -Path $Path)) {
            $xml = Read-MsBuildProject -Path $project
            $projectDir = Split-Path -Parent $project

            foreach ($node in $xml.SelectNodes("//*[local-name()='ItemGroup']/*[@Include]")) {
                if ($IgnoreItemType -contains $node.LocalName) {
                    continue
                }

                foreach ($include in ($node.GetAttribute('Include') -split ';')) {
                    $include = $include.Trim()
                    if (-not $include -or $include -match '\$\(|@\(|\*|\?') {
                        continue
                    }

                    # MSBuild escapes special characters as %XX in item specs.
                    $relativePath = [uri]::UnescapeDataString($include)
                    if ([IO.Path]::IsPathRooted($relativePath)) {
                        $expectedPath = $relativePath
                    }
                    else {
                        $expectedPath = Join-Path $projectDir $relativePath
                    }

                    if (-not (Test-Path -LiteralPath $expectedPath)) {
                        [pscustomobject]@{
                            Project      = $project
                            ItemType     = $node.LocalName
                            Include      = $include
                            ExpectedPath = $expectedPath
                        }
                    }
                }
            }
        }
    }
}
