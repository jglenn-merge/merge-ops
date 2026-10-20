function Export-IISCertificate {
    <#
    .SYNOPSIS
    Exports the certificate behind every HTTPS binding in IIS to password-protected PFX files.

    .DESCRIPTION
    Each certificate is exported once, even when several bindings share it. Files are named after the certificate's common name
    and the start of its thumbprint. Certificates are read from the store each binding points at, so SNI certificates in the
    WebHosting store are included. Certificates without an exportable private key are reported as Failed. Requires an elevated session.

    .PARAMETER Destination
    Folder to write PFX files to. Created if it does not exist.

    .PARAMETER Password
    Password that protects the exported PFX files.

    .PARAMETER SiteName
    Site name filter. Wildcards are supported.

    .EXAMPLE
    Export-IISCertificate -Destination C:\certs\export -Password (Read-Host -AsSecureString 'PFX password')

    .EXAMPLE
    Export-IISCertificate -Destination C:\certs\export -Password $pfxPassword -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $true)]
        [securestring]$Password,

        [string]$SiteName = '*'
    )

    Assert-Administrator

    $destinationPath = Resolve-FullPath -Path $Destination
    if (-not (Test-Path -LiteralPath $destinationPath)) {
        New-Item -ItemType Directory -Path $destinationPath | Out-Null
    }

    $bindings = Get-IISBindingInfo -SiteName $SiteName | Where-Object { $_.Protocol -eq 'https' -and $_.CertificateHash }
    $invalidChars = [IO.Path]::GetInvalidFileNameChars()

    foreach ($group in ($bindings | Group-Object -Property CertificateHash)) {
        $thumbprint = $group.Name
        $store = $group.Group[0].CertificateStoreName
        if (-not $store) {
            $store = 'My'
        }
        $sites = ($group.Group.Site | Select-Object -Unique) -join ', '

        $result = [ordered]@{
            Thumbprint = $thumbprint
            Subject    = $null
            NotAfter   = $null
            Sites      = $sites
            FilePath   = $null
            Status     = $null
            Error      = $null
        }

        $certificate = Get-Item -LiteralPath "Cert:\LocalMachine\$store\$thumbprint" -ErrorAction SilentlyContinue
        if (-not $certificate) {
            $result.Status = 'NotFound'
            $result.Error = "Certificate $thumbprint was not found in Cert:\LocalMachine\$store."
            Write-Warning $result.Error
            [pscustomobject]$result
            continue
        }

        $commonName = $certificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
        $safeName = -join ($commonName.ToCharArray() | ForEach-Object { if ($invalidChars -contains $_) { '_' } else { $_ } })
        $filePath = Join-Path $destinationPath ("{0}-{1}.pfx" -f $safeName, $thumbprint.Substring(0, 8))

        $result.Subject = $certificate.Subject
        $result.NotAfter = $certificate.NotAfter
        $result.FilePath = $filePath

        if ($PSCmdlet.ShouldProcess("$($certificate.Subject) ($thumbprint)", "Export to $filePath")) {
            try {
                Export-PfxCertificate -Cert $certificate -FilePath $filePath -Password $Password -ErrorAction Stop | Out-Null
                $result.Status = 'Exported'
            }
            catch {
                $result.Status = 'Failed'
                $result.Error = $_.Exception.Message
                Write-Warning "Could not export $($certificate.Subject): $($result.Error)"
            }
        }
        else {
            $result.Status = 'Skipped'
        }

        [pscustomobject]$result
    }
}
