function Get-IISBindingInfo {
    [CmdletBinding()]
    param(
        [string]$SiteName = '*'
    )

    Import-WebAdministration

    foreach ($site in (Get-Website | Where-Object { $_.Name -like $SiteName })) {
        foreach ($binding in $site.bindings.Collection) {
            $parsed = ConvertFrom-IISBindingInformation -BindingInformation ([string]$binding.bindingInformation)

            [pscustomobject]@{
                Site                 = $site.Name
                SiteState            = $site.State
                Protocol             = $binding.protocol
                IPAddress            = $parsed.IPAddress
                Port                 = $parsed.Port
                HostName             = $parsed.HostName
                BindingInformation   = $parsed.BindingInformation
                CertificateHash      = [string]$binding.certificateHash
                CertificateStoreName = [string]$binding.certificateStoreName
                SslFlags             = $binding.sslFlags
            }
        }
    }
}
