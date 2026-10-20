# Sends one command as a RESP array and returns the first reply line (for example "+PONG" or "-ERR ...").
# Only single-line replies are read, which covers AUTH and PING.
function Send-RedisCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory = $true)]
        [string[]]$Argument
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("*$($Argument.Count)`r`n")
    foreach ($item in $Argument) {
        [void]$builder.Append("`$$($utf8.GetByteCount($item))`r`n$item`r`n")
    }

    $bytes = $utf8.GetBytes($builder.ToString())
    $Stream.Write($bytes, 0, $bytes.Length)
    $Stream.Flush()

    # Read byte by byte so nothing past the reply line gets buffered and lost.
    $reply = New-Object System.Collections.Generic.List[byte]
    while ($true) {
        $next = $Stream.ReadByte()
        if ($next -lt 0) {
            throw "The server closed the connection before replying."
        }
        if ($next -eq 10) {
            break
        }
        if ($next -ne 13) {
            $reply.Add([byte]$next)
        }
    }
    return $utf8.GetString($reply.ToArray())
}
