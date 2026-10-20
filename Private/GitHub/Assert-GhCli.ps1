function Assert-GhCli {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name gh -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'The GitHub CLI (gh) is required. Install it from https://cli.github.com and run "gh auth login".'
    }
}
