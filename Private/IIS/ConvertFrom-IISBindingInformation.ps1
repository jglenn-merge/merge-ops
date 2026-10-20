# Parses an IIS bindingInformation string ("ip:port:host"). IPv6 addresses contain colons, so the port and host are matched from the right.
# Non-HTTP bindings such as net.tcp ("808:*") do not match and come back with only the raw value.
function ConvertFrom-IISBindingInformation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$BindingInformation
    )

    $ipAddress = $null
    $port = $null
    $hostName = $null
    if ($BindingInformation -match '^(?<ip>.*):(?<port>\d+):(?<host>[^:]*)$') {
        $ipAddress = $Matches['ip']
        $port = [int]$Matches['port']
        $hostName = $Matches['host']
    }

    [pscustomobject]@{
        IPAddress          = $ipAddress
        Port               = $port
        HostName           = $hostName
        BindingInformation = $BindingInformation
    }
}
