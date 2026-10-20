function Test-SmtpConnection {
    <#
    .SYNOPSIS
    Tests TCP connectivity to an SMTP server and optionally sends a test message.

    .DESCRIPTION
    Always checks that the server accepts a TCP connection on -Port. When -To is supplied, it also sends a test message, which
    is the only way to confirm that -Credential is accepted, because System.Net.Mail authenticates as part of sending.

    .PARAMETER SmtpServer
    SMTP host name.

    .PARAMETER Port
    SMTP port. 587 is submission with STARTTLS. System.Net.Mail does not support implicit TLS on 465.

    .PARAMETER Credential
    SMTP credential. Only used when a message is sent.

    .PARAMETER EnableSsl
    Use STARTTLS when sending.

    .PARAMETER From
    Sender address. Required with -To.

    .PARAMETER To
    Recipient addresses. When omitted, only the TCP check runs.

    .PARAMETER Subject
    Subject of the test message.

    .PARAMETER TimeoutMs
    Timeout for the TCP check and the send.

    .EXAMPLE
    Test-SmtpConnection -SmtpServer smtp.example.com

    .EXAMPLE
    Test-SmtpConnection -SmtpServer smtp.example.com -Credential (Get-Credential) -From admin@example.com -To me@example.com
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SmtpServer,

        [int]$Port = 587,

        [pscredential]$Credential,

        [bool]$EnableSsl = $true,

        [string]$From,

        [string[]]$To,

        [string]$Subject = 'SMTP connection test',

        [int]$TimeoutMs = 10000
    )

    if ($To -and -not $From) {
        throw 'A -From address is required when -To is specified.'
    }

    $result = [ordered]@{
        SmtpServer   = $SmtpServer
        Port         = $Port
        TcpConnected = $false
        MessageSent  = $null
        Error        = $null
    }

    $result.TcpConnected = Test-TcpPort -ComputerName $SmtpServer -Port $Port -TimeoutMs $TimeoutMs
    if (-not $result.TcpConnected) {
        $result.Error = "Could not open a TCP connection to ${SmtpServer}:$Port."
        return [pscustomobject]$result
    }

    if ($To) {
        $client = $null
        $message = $null
        try {
            $client = New-Object System.Net.Mail.SmtpClient($SmtpServer, $Port)
            $client.EnableSsl = $EnableSsl
            $client.Timeout = $TimeoutMs
            if ($Credential) {
                $client.Credentials = $Credential.GetNetworkCredential()
            }

            $message = New-Object System.Net.Mail.MailMessage
            $message.From = $From
            foreach ($address in $To) {
                $message.To.Add($address)
            }
            $message.Subject = $Subject
            $message.Body = "Test message sent by Test-SmtpConnection from $env:COMPUTERNAME at $(Get-Date -Format o)."

            $client.Send($message)
            $result.MessageSent = $true
        }
        catch {
            $result.MessageSent = $false
            $result.Error = $_.Exception.GetBaseException().Message
        }
        finally {
            if ($message) { $message.Dispose() }
            if ($client) { $client.Dispose() }
        }
    }

    [pscustomobject]$result
}
