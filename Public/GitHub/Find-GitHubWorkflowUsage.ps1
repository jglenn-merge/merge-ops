function Find-GitHubWorkflowUsage {
    <#
    .SYNOPSIS
    Searches GitHub Actions workflow files across every repo in an organization.

    .DESCRIPTION
    Lists repos with the GitHub CLI, reads each .github/workflows/*.yml file on the default branch, and outputs one object
    per workflow file that contains -Pattern. Useful for finding every repo that uses a reusable workflow, runner image,
    or action version before changing it.

    Requires the GitHub CLI (gh), signed in with access to the organization. Archived repos are skipped unless
    -IncludeArchived is set.

    .PARAMETER Organization
    GitHub organization name.

    .PARAMETER Pattern
    Text to search for. Treated as a literal string unless -Regex is set.

    .PARAMETER Regex
    Treat -Pattern as a regular expression.

    .PARAMETER IncludeArchived
    Also search archived repos.

    .PARAMETER Limit
    Maximum number of repos to list.

    .EXAMPLE
    Find-GitHubWorkflowUsage -Organization mergeworld -Pattern 'frontend-ci'

    .EXAMPLE
    Find-GitHubWorkflowUsage -Organization mergeworld -Pattern 'actions/checkout@v[23]' -Regex | Format-Table Repository, Workflow, LineNumber
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [switch]$Regex,

        [switch]$IncludeArchived,

        [int]$Limit = 1000
    )

    Assert-GhCli

    if ($Regex) {
        $expression = $Pattern
    }
    else {
        $expression = [regex]::Escape($Pattern)
    }

    $repos = @(Get-GhOrgRepository -Organization $Organization -Limit $Limit | Where-Object { $IncludeArchived -or -not $_.isArchived })
    $current = 0

    foreach ($repo in $repos) {
        $current++
        Write-Progress -Activity 'Searching workflows' -Status $repo.nameWithOwner -PercentComplete (($current / $repos.Count) * 100)

        try {
            $files = @(Invoke-GhApi -Endpoint "repos/$($repo.nameWithOwner)/contents/.github/workflows")
        }
        catch {
            Write-Verbose "No workflows found in $($repo.nameWithOwner)."
            continue
        }

        foreach ($file in ($files | Where-Object { $_.name -match '\.ya?ml$' })) {
            try {
                $item = Invoke-GhApi -Endpoint "repos/$($repo.nameWithOwner)/contents/$($file.path)"
            }
            catch {
                Write-Warning "Could not read $($file.path) in $($repo.nameWithOwner): $($_.Exception.Message)"
                continue
            }

            $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($item.content))
            $lines = $text -split "\r?\n"
            $matchedLines = @(for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match $expression) { $i }
            })

            if ($matchedLines.Count -gt 0) {
                [pscustomobject]@{
                    Repository = $repo.nameWithOwner
                    Workflow   = $file.name
                    Path       = $file.path
                    MatchCount = $matchedLines.Count
                    LineNumber = $matchedLines[0] + 1
                    Line       = $lines[$matchedLines[0]].Trim()
                }
            }
        }
    }
    Write-Progress -Activity 'Searching workflows' -Completed
}
