function Remove-DotNetPackagesConfig {
    <#
    .SYNOPSIS
    Removes packages.config-style NuGet wiring from projects, optionally replacing it with PackageReference items.

    .DESCRIPTION
    For each project that has a packages.config next to it, this removes:
    - Reference items whose HintPath points into a packages folder
    - Import elements that load .props or .targets from a packages folder
    - The EnsureNuGetPackageBuildImports target
    - The packages.config item and the packages.config file

    With -AddPackageReference, every package listed in packages.config is added back as a PackageReference with the same
    version. packages.config lists transitive dependencies too, so prune the new list afterwards.

    This edits the project XML directly, so it runs outside Visual Studio. Run it on a clean working tree so the changes can be
    reviewed as a diff.

    .PARAMETER Path
    Project or solution files. FileInfo objects can be piped in.

    .PARAMETER AddPackageReference
    Add a PackageReference for each package that was in packages.config.

    .EXAMPLE
    Remove-DotNetPackagesConfig -Path .\Website.sln -AddPackageReference -WhatIf

    .EXAMPLE
    Remove-DotNetPackagesConfig -Path .\src\Feature\Navigation\Feature.Navigation.csproj -AddPackageReference -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [switch]$AddPackageReference
    )

    process {
        foreach ($project in (Resolve-ProjectFile -Path $Path)) {
            $packagesConfigPath = Join-Path (Split-Path -Parent $project) 'packages.config'
            if (-not (Test-Path -LiteralPath $packagesConfigPath)) {
                Write-Verbose "No packages.config found for $project."
                continue
            }

            $packagesXml = New-Object System.Xml.XmlDocument
            $packagesXml.Load($packagesConfigPath)
            $packages = @($packagesXml.SelectNodes('/packages/package'))

            $xml = Read-MsBuildProject -Path $project
            $lower = "translate({0}, 'ACEGKPS', 'acegkps')"
            $references = @($xml.SelectNodes("//*[local-name()='Reference'][*[local-name()='HintPath' and contains($($lower -f '.'), 'packages\')]]"))
            $imports = @($xml.SelectNodes("//*[local-name()='Import'][contains($($lower -f '@Project'), 'packages\')]"))
            $targets = @($xml.SelectNodes("//*[local-name()='Target'][@Name='EnsureNuGetPackageBuildImports']"))
            $configItems = @($xml.SelectNodes("//*[local-name()='ItemGroup']/*[@Include='packages.config']"))

            $description = "Remove packages.config ($($packages.Count) packages), $($references.Count) references, and $($imports.Count) imports"
            if (-not $PSCmdlet.ShouldProcess($project, $description)) {
                continue
            }

            foreach ($node in @($references + $imports + $targets + $configItems)) {
                Remove-XmlNode -Node $node
            }
            foreach ($emptyGroup in @($xml.SelectNodes("//*[local-name()='ItemGroup'][not(*)]"))) {
                Remove-XmlNode -Node $emptyGroup
            }

            $added = 0
            if ($AddPackageReference -and $packages.Count -gt 0) {
                $root = $xml.DocumentElement
                $namespace = $root.NamespaceURI
                $group = $xml.CreateElement('ItemGroup', $namespace)

                foreach ($package in $packages) {
                    $reference = $xml.CreateElement('PackageReference', $namespace)
                    $reference.SetAttribute('Include', $package.GetAttribute('id'))
                    $reference.SetAttribute('Version', $package.GetAttribute('version'))
                    [void]$group.AppendChild($xml.CreateWhitespace("`r`n    "))
                    [void]$group.AppendChild($reference)
                    $added++
                }
                [void]$group.AppendChild($xml.CreateWhitespace("`r`n  "))

                [void]$root.AppendChild($xml.CreateWhitespace("  "))
                [void]$root.AppendChild($group)
                [void]$root.AppendChild($xml.CreateWhitespace("`r`n"))
            }

            $xml.Save($project)
            Remove-Item -LiteralPath $packagesConfigPath -Force -Confirm:$false

            [pscustomobject]@{
                Project                = $project
                PackagesConfigEntries  = $packages.Count
                ReferencesRemoved      = $references.Count
                ImportsRemoved         = $imports.Count
                PackageReferencesAdded = $added
            }
        }
    }
}
