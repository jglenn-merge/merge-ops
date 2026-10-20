@{
    RootModule           = 'MergeOps.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'b893b423-19f8-48b4-a7b8-e00779f2ec1d'
    Author               = 'Jeff Glenn'
    CompanyName          = 'Merge'
    Copyright            = '(c) Merge. All rights reserved.'
    Description          = 'Operational utilities for web diagnostics, connectivity checks, IIS, Windows Server maintenance, release folders, Sitecore deploys, .NET project maintenance, and GitHub org administration.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        # Web
        'Find-WebExternalDomain'
        'Invoke-WebWarmup'
        'Measure-WebLatency'
        'Test-WebLoadBalancing'
        'Watch-WebEndpoint'

        # Connectivity
        'Test-RedisConnection'
        'Test-SmtpConnection'
        'Test-SqlConnection'

        # IIS
        'ConvertFrom-IISLog'
        'Export-IISCertificate'
        'Get-IISBindingReport'

        # Server
        'Find-LongFilePath'
        'Remove-StaleFile'
        'Repair-StoppedService'

        # Release
        'Compress-ReleaseFolder'
        'New-ReleaseFolder'

        # Sitecore
        'Clear-SitecoreBinFolder'

        # DotNet
        'Find-DotNetMissingFile'
        'Remove-DotNetPackagesConfig'

        # GitHub
        'Find-GitHubWorkflowUsage'
        'Set-GitHubRepoVisibility'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags = @('IIS', 'Sitecore', 'Deployment', 'Diagnostics', 'GitHub')
        }
    }
}
