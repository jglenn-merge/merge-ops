function Get-IISBindingReport {
    <#
    .SYNOPSIS
    Lists IIS site bindings, with certificate details for HTTPS bindings.

    .DESCRIPTION
    Returns one object per binding. HTTPS bindings include the bound certificate's subject and expiry date, looked up in the
    store the binding points at (usually My or WebHosting). Requires an elevated session.

    .PARAMETER SiteName
    Site name filter. Wildcards are supported.

    .PARAMETER Protocol
    Only return bindings for this protocol, for example https.

    .EXAMPLE
    Get-IISBindingReport | Format-Table Site, Protocol, HostName, Port, CertificateExpires

    .EXAMPLE
    Get-IISBindingReport -Protocol https | Where-Object CertificateExpires -lt (Get-Date).AddDays(30)
    #>
    [CmdletBinding()]
    param(
        [string]$SiteName = '*',

        [string]$Protocol
    )

    Assert-Administrator

    $bindings = Get-IISBindingInfo -SiteName $SiteName
    if ($Protocol) {
        $bindings = $bindings | Where-Object { $_.Protocol -eq $Protocol }
    }

    foreach ($binding in $bindings) {
        $subject = $null
        $expires = $null
        if ($binding.CertificateHash) {
            $store = $binding.CertificateStoreName
            if (-not $store) {
                $store = 'My'
            }
            $certificate = Get-Item -LiteralPath "Cert:\LocalMachine\$store\$($binding.CertificateHash)" -ErrorAction SilentlyContinue
            if ($certificate) {
                $subject = $certificate.Subject
                $expires = $certificate.NotAfter
            }
        }

        [pscustomobject]@{
            Site                  = $binding.Site
            SiteState             = $binding.SiteState
            Protocol              = $binding.Protocol
            IPAddress             = $binding.IPAddress
            Port                  = $binding.Port
            HostName              = $binding.HostName
            BindingInformation    = $binding.BindingInformation
            SslFlags              = $binding.SslFlags
            CertificateThumbprint = $binding.CertificateHash
            CertificateStore      = $binding.CertificateStoreName
            CertificateSubject    = $subject
            CertificateExpires    = $expires
        }
    }
}
