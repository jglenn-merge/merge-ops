function Test-TcpPort {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [int]$TimeoutMs = 5000
    )

    try {
        $client = New-TcpClient -ComputerName $ComputerName -Port $Port -TimeoutMs $TimeoutMs
        $client.Close()
        return $true
    }
    catch {
        Write-Verbose "TCP connection to ${ComputerName}:$Port failed: $($_.Exception.GetBaseException().Message)"
        return $false
    }
}
