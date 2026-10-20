function Invoke-WebWarmup {
    <#
    .SYNOPSIS
    Requests a site's base URL and a list of pages to warm caches after a deploy.

    .DESCRIPTION
    Requests the base URL first. If -AuthPattern matches the response body (for example a staging login page), an auth cookie
    is added to the session and the base URL is requested again. Each page in -Path is then requested in order.

    Every page is attempted even if an earlier one fails. If any request fails, the function throws after the last page so a
    deployment step still fails.

    .PARAMETER BaseUrl
    Root URL of the site, for example https://cm.example.com.

    .PARAMETER Path
    Relative paths to request. Each entry can also be a newline-delimited list, which is how Octopus multi-line variables arrive.

    .PARAMETER Credential
    Basic auth credential for sites behind basic auth.

    .PARAMETER AuthPattern
    Regex that identifies a login page in the base URL response. When it matches, the auth cookie is added and the request is retried.

    .PARAMETER AuthCookieName
    Name of the cookie that bypasses the login page.

    .PARAMETER AuthCookieValue
    Value of the cookie that bypasses the login page.

    .PARAMETER TimeoutSec
    Per-request timeout. The default is high because cold Sitecore instances can take minutes to answer the first request.

    .EXAMPLE
    Invoke-WebWarmup -BaseUrl https://www.example.com -Path 'about', 'contact', 'news'

    .EXAMPLE
    $cred = Get-Credential
    Invoke-WebWarmup -BaseUrl https://stage.example.com -Path $OctopusParameters['WarmupPages'] -Credential $cred -AuthPattern 'sc-auth-form'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [string[]]$Path = @(),

        [pscredential]$Credential,

        [string]$AuthPattern,

        [string]$AuthCookieName = 'sc-auth-successful',

        [string]$AuthCookieValue = 'true',

        [int]$TimeoutSec = 300
    )

    $base = $BaseUrl.TrimEnd('/')
    $headers = @{}
    if ($Credential) {
        $headers = New-BasicAuthHeader -Credential $Credential
    }
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $outputProperties = 'Timestamp', 'Uri', 'Success', 'StatusCode', 'ElapsedMs', 'Error'

    Write-Verbose "Fetching $base"
    $result = Invoke-TimedRequest -Uri $base -Headers $headers -WebSession $session -TimeoutSec $TimeoutSec -IncludeContent
    if (-not $result.Success) {
        throw "Warmup request to $base failed: $($result.Error)"
    }

    if ($AuthPattern -and $result.Content -match $AuthPattern) {
        Write-Verbose "Login page detected at $base. Adding the $AuthCookieName cookie and retrying."
        $cookie = New-Object System.Net.Cookie($AuthCookieName, $AuthCookieValue)
        $session.Cookies.Add([uri]$base, $cookie)

        $result = Invoke-TimedRequest -Uri $base -Headers $headers -WebSession $session -TimeoutSec $TimeoutSec
        if (-not $result.Success) {
            throw "Warmup request to $base failed after adding the auth cookie: $($result.Error)"
        }
    }
    $result | Select-Object -Property $outputProperties

    $pages = @($Path | ForEach-Object { $_ -split "\r?\n" } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $failed = 0
    foreach ($page in $pages) {
        $uri = "$base/$($page.TrimStart('/'))"
        Write-Verbose "Fetching $uri"
        $result = Invoke-TimedRequest -Uri $uri -Headers $headers -WebSession $session -TimeoutSec $TimeoutSec
        if (-not $result.Success) {
            $failed++
            Write-Warning "Did not get a successful response from ${uri}: $($result.Error)"
        }
        $result | Select-Object -Property $outputProperties
    }

    if ($failed -gt 0) {
        throw "$failed of $($pages.Count) warmup page requests failed."
    }
}
