function Test-RedisConnection {
    <#
    .SYNOPSIS
    Connects to a Redis server, optionally authenticates, and sends PING.

    .DESCRIPTION
    Speaks the Redis protocol directly over TCP, so it needs no Redis client or Python on the machine. Use -UseTls for Azure
    Cache for Redis, which disables the non-TLS port (6379) by default and listens for TLS on 6380.

    .PARAMETER HostName
    Redis host name, without a port.

    .PARAMETER Port
    Redis port. Defaults to 6380 with -UseTls and 6379 without.

    .PARAMETER UseTls
    Wrap the connection in TLS 1.2.

    .PARAMETER UserName
    ACL user name for Redis 6 and later. Omit for password-only AUTH, which is what Azure access keys use.

    .PARAMETER Password
    Password or access key.

    .PARAMETER TimeoutMs
    Connect and read timeout.

    .EXAMPLE
    Test-RedisConnection -HostName client-uat-redis.redis.cache.windows.net -UseTls -Password (Read-Host -AsSecureString 'Access key')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [int]$Port,

        [switch]$UseTls,

        [string]$UserName,

        [securestring]$Password,

        [int]$TimeoutMs = 5000
    )

    if (-not $PSBoundParameters.ContainsKey('Port')) {
        if ($UseTls) { $Port = 6380 } else { $Port = 6379 }
    }

    $result = [ordered]@{
        HostName      = $HostName
        Port          = $Port
        Tls           = [bool]$UseTls
        Connected     = $false
        Authenticated = $null
        Success       = $false
        Response      = $null
        ElapsedMs     = $null
        Error         = $null
    }

    $client = $null
    $stream = $null
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $client = New-TcpClient -ComputerName $HostName -Port $Port -TimeoutMs $TimeoutMs
        $result.Connected = $true
        $stream = $client.GetStream()

        if ($UseTls) {
            $sslStream = New-Object System.Net.Security.SslStream($stream, $false)
            $sslStream.AuthenticateAsClient($HostName, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false)
            $stream = $sslStream
        }

        if ($Password) {
            $plainPassword = (New-Object System.Management.Automation.PSCredential('redis', $Password)).GetNetworkCredential().Password
            if ($UserName) {
                $command = @('AUTH', $UserName, $plainPassword)
            }
            else {
                $command = @('AUTH', $plainPassword)
            }
            $reply = Send-RedisCommand -Stream $stream -Argument $command
            $result.Authenticated = $reply -like '+OK*'
            if (-not $result.Authenticated) {
                throw "AUTH was rejected: $reply"
            }
        }

        $reply = Send-RedisCommand -Stream $stream -Argument @('PING')
        $result.Response = $reply
        if ($reply -notlike '+PONG*') {
            throw "Unexpected reply to PING: $reply"
        }
        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.GetBaseException().Message
    }
    finally {
        $timer.Stop()
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Close() }
    }
    $result.ElapsedMs = [math]::Round($timer.Elapsed.TotalMilliseconds, 1)

    [pscustomobject]$result
}
