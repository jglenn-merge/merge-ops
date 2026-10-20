function New-BasicAuthHeader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [pscredential]$Credential
    )

    $pair = "{0}:{1}" -f $Credential.UserName, $Credential.GetNetworkCredential().Password
    $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
    @{ Authorization = "Basic $encoded" }
}
