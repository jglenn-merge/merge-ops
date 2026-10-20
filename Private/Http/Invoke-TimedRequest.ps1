# Single HTTP request wrapper shared by the Web functions. It never throws on HTTP errors.
# It returns a result object so callers can decide what counts as a failure.
function Invoke-TimedRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [hashtable]$Headers = @{},

        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,

        [int]$TimeoutSec = 100,

        [switch]$DisableKeepAlive,

        [switch]$IncludeContent
    )

    $request = @{
        Uri             = $Uri
        Headers         = $Headers
        UseBasicParsing = $true
        TimeoutSec      = $TimeoutSec
        ErrorAction     = 'Stop'
    }
    if ($WebSession) {
        $request.WebSession = $WebSession
    }
    if ($DisableKeepAlive) {
        $request.DisableKeepAlive = $true
    }

    $response = $null
    $failure = $null
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest @request
    }
    catch {
        $failure = $_
    }
    $timer.Stop()

    $statusCode = $null
    $responseHeaders = $null
    $content = $null
    $errorMessage = $null
    $exceptionType = $null

    if ($response) {
        $statusCode = [int]$response.StatusCode
        $responseHeaders = $response.Headers
        if ($IncludeContent) {
            $content = $response.Content
        }
    }
    else {
        # Windows PowerShell surfaces HttpWebResponse here, PowerShell 7 surfaces HttpResponseMessage. Both expose StatusCode.
        if ($failure.Exception.Response) {
            $statusCode = [int]$failure.Exception.Response.StatusCode
        }
        $errorMessage = $failure.Exception.Message
        $exceptionType = $failure.Exception.GetType().FullName
    }

    [pscustomobject]@{
        Timestamp     = Get-Date
        Uri           = $Uri
        Success       = $null -ne $response
        StatusCode    = $statusCode
        ElapsedMs     = [math]::Round($timer.Elapsed.TotalMilliseconds, 1)
        Headers       = $responseHeaders
        Content       = $content
        Error         = $errorMessage
        ExceptionType = $exceptionType
    }
}
