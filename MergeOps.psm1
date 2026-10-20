#Get public and private function definition files.
$Private = @( Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue )
$Public  = @( Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue )

#Dot source the files
foreach ($import in @($Private + $Public)) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

# Windows PowerShell defaults to TLS 1.0/1.1 on older .NET configurations. Add TLS 1.2 without removing anything already enabled.
if ($PSVersionTable.PSEdition -ne 'Core') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

Export-ModuleMember -Function $Public.BaseName
