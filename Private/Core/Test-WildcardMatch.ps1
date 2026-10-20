function Test-WildcardMatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$Value,

        [string[]]$Pattern
    )

    foreach ($p in $Pattern) {
        if ($Value -like $p) {
            return $true
        }
    }
    return $false
}
