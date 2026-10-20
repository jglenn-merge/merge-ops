function Invoke-GhApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [hashtable]$Field = @{}
    )

    $arguments = @('api', $Endpoint, '--method', $Method)
    foreach ($key in $Field.Keys) {
        $arguments += '-f'
        $arguments += "$key=$($Field[$key])"
    }

    $json = Invoke-GhCommand -Argument $arguments
    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }
    $parsed = $json | ConvertFrom-Json
    return $parsed
}
