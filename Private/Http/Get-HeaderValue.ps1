# Response header values are strings in Windows PowerShell and string arrays in PowerShell 7. Normalize to one string.
function Get-HeaderValue {
    [CmdletBinding()]
    param(
        $Headers,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not $Headers -or -not $Headers.ContainsKey($Name)) {
        return $null
    }
    return (@($Headers[$Name]) -join ', ')
}
