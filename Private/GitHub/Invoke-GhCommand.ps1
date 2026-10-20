# Runs gh and returns stdout as one string. Throws with gh's stderr when the exit code is non-zero.
function Invoke-GhCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Argument
    )

    # Windows PowerShell turns native stderr into error records, which would terminate under a caller's ErrorActionPreference of Stop.
    $ErrorActionPreference = 'Continue'

    $output = & gh @Argument 2>&1
    $exitCode = $LASTEXITCODE

    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() })

    if ($exitCode -ne 0) {
        throw "gh $($Argument[0..1] -join ' ') failed with exit code ${exitCode}: $($stderr -join ' ')"
    }
    return ($stdout -join "`n")
}
