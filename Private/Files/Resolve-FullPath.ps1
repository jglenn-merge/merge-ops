# Resolves a path that may not exist yet against the current PowerShell location. .NET APIs resolve relative paths against the process directory instead.
function Resolve-FullPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}
