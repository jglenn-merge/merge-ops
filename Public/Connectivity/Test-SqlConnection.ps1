function Test-SqlConnection {
    <#
    .SYNOPSIS
    Opens and closes a SQL Server connection to confirm a server, database, and login are reachable.

    .DESCRIPTION
    Accepts either a full connection string or a server and database. With a server and no -Credential, Windows integrated
    authentication is used. The connection string is never written to output.

    .PARAMETER ConnectionString
    Full ADO.NET connection string.

    .PARAMETER ServerInstance
    Server name, optionally with an instance or port (sql01\INST or sql01,1433).

    .PARAMETER Database
    Database to connect to.

    .PARAMETER Credential
    SQL authentication login. Omit to use integrated authentication.

    .PARAMETER ConnectTimeout
    Connection timeout in seconds.

    .EXAMPLE
    Test-SqlConnection -ServerInstance sql01 -Database client_Master

    .EXAMPLE
    Test-SqlConnection -ConnectionString $connectionStrings['master']
    #>
    [CmdletBinding(DefaultParameterSetName = 'Server')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ConnectionString')]
        [string]$ConnectionString,

        [Parameter(Mandatory = $true, ParameterSetName = 'Server', Position = 0)]
        [string]$ServerInstance,

        [Parameter(ParameterSetName = 'Server')]
        [string]$Database = 'master',

        [Parameter(ParameterSetName = 'Server')]
        [pscredential]$Credential,

        [int]$ConnectTimeout = 15
    )

    # PowerShell treats the builder as a dictionary, so property syntax would add bogus keys. Use connection string keywords.
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    if ($PSCmdlet.ParameterSetName -eq 'ConnectionString') {
        $builder.set_ConnectionString($ConnectionString)
        if ($PSBoundParameters.ContainsKey('ConnectTimeout')) {
            $builder['Connect Timeout'] = $ConnectTimeout
        }
    }
    else {
        $builder['Data Source'] = $ServerInstance
        $builder['Initial Catalog'] = $Database
        $builder['Connect Timeout'] = $ConnectTimeout
        if ($Credential) {
            $builder['User ID'] = $Credential.UserName
            $builder['Password'] = $Credential.GetNetworkCredential().Password
        }
        else {
            $builder['Integrated Security'] = $true
        }
    }

    $result = [ordered]@{
        DataSource    = $builder['Data Source']
        Database      = $builder['Initial Catalog']
        Success       = $false
        ServerVersion = $null
        ElapsedMs     = $null
        Error         = $null
    }

    $connection = New-Object System.Data.SqlClient.SqlConnection($builder.get_ConnectionString())
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $connection.Open()
        $result.Success = $true
        $result.ServerVersion = $connection.ServerVersion
    }
    catch {
        $result.Error = $_.Exception.GetBaseException().Message
    }
    finally {
        $timer.Stop()
        $connection.Dispose()
    }
    $result.ElapsedMs = [math]::Round($timer.Elapsed.TotalMilliseconds, 1)

    [pscustomobject]$result
}
