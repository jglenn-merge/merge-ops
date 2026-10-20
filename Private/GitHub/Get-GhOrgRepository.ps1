function Get-GhOrgRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [int]$Limit = 1000
    )

    $json = Invoke-GhCommand -Argument @('repo', 'list', $Organization, '--limit', $Limit, '--json', 'name,nameWithOwner,visibility,isArchived')

    # Assign before returning. Windows PowerShell's ConvertFrom-Json emits a JSON array as a single object.
    $repos = $json | ConvertFrom-Json
    return $repos
}
