function Import-WebAdministration {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -Name WebAdministration)) {
        Import-Module WebAdministration -ErrorAction Stop -Verbose:$false
    }
}
