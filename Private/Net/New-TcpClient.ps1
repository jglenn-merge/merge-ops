# Returns a connected TcpClient or throws. The caller owns closing it.
function New-TcpClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [int]$TimeoutMs = 5000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            throw "Timed out after $TimeoutMs ms connecting to ${ComputerName}:$Port."
        }
        $client.EndConnect($pending)
    }
    catch {
        $client.Close()
        throw
    }

    $client.ReceiveTimeout = $TimeoutMs
    $client.SendTimeout = $TimeoutMs
    return $client
}
