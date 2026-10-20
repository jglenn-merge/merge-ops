function Set-GitHubRepoVisibility {
    <#
    .SYNOPSIS
    Changes the visibility of repos in a GitHub organization in bulk.

    .DESCRIPTION
    Selects repos in -Organization whose current visibility is -CurrentVisibility, optionally narrowed by -Name and -Exclude,
    and changes each one to -Visibility. Every change asks for confirmation by default. Run with -WhatIf first to see the full
    list, then use -Confirm:$false once the list is correct.

    Archived repos are skipped unless -IncludeArchived is set, because GitHub rejects visibility changes on archived repos.
    Requires the GitHub CLI (gh), signed in as an organization owner.

    .PARAMETER Organization
    GitHub organization name.

    .PARAMETER Visibility
    Visibility to change to.

    .PARAMETER CurrentVisibility
    Only change repos that currently have this visibility.

    .PARAMETER Name
    Repo name patterns to include. Wildcards are supported. All repos are included when omitted.

    .PARAMETER Exclude
    Repo name patterns to leave alone. Wildcards are supported.

    .PARAMETER IncludeArchived
    Also attempt archived repos.

    .PARAMETER Limit
    Maximum number of repos to list.

    .EXAMPLE
    Set-GitHubRepoVisibility -Organization mergeworld -Visibility internal -Exclude 'actions-sandbox' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [ValidateSet('public', 'private', 'internal')]
        [string]$Visibility,

        [ValidateSet('public', 'private', 'internal')]
        [string]$CurrentVisibility = 'private',

        [string[]]$Name,

        [string[]]$Exclude = @(),

        [switch]$IncludeArchived,

        [int]$Limit = 1000
    )

    Assert-GhCli

    if ($Visibility -eq $CurrentVisibility) {
        throw "-Visibility and -CurrentVisibility are both '$Visibility'. Nothing would change."
    }

    $repos = Get-GhOrgRepository -Organization $Organization -Limit $Limit | Where-Object {
        $_.visibility -eq $CurrentVisibility -and
        ($IncludeArchived -or -not $_.isArchived) -and
        (-not $Name -or (Test-WildcardMatch -Value $_.name -Pattern $Name)) -and
        -not (Test-WildcardMatch -Value $_.name -Pattern $Exclude)
    }

    foreach ($repo in $repos) {
        $status = 'Skipped'
        $errorMessage = $null

        if ($PSCmdlet.ShouldProcess($repo.nameWithOwner, "Change visibility from $CurrentVisibility to $Visibility")) {
            try {
                Invoke-GhApi -Endpoint "repos/$($repo.nameWithOwner)" -Method PATCH -Field @{ visibility = $Visibility } | Out-Null
                $status = 'Updated'
            }
            catch {
                $status = 'Failed'
                $errorMessage = $_.Exception.Message
                Write-Warning "Could not update $($repo.nameWithOwner): $errorMessage"
            }
        }

        [pscustomobject]@{
            Repository = $repo.nameWithOwner
            From       = $CurrentVisibility
            To         = $Visibility
            Status     = $status
            Error      = $errorMessage
        }
    }
}
