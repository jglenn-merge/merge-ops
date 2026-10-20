function Find-LongFilePath {
    <#
    .SYNOPSIS
    Finds files whose full path is at or above a length threshold.

    .DESCRIPTION
    Useful before a build or deploy, because MSBuild, TDS, and many Windows tools fail on paths of 260 characters or more.
    The search uses extended-length (\\?\) paths, so files already past the limit are still found.

    .PARAMETER Path
    Root folder to search.

    .PARAMETER MinimumLength
    Report files whose full path is at least this many characters.

    .EXAMPLE
    Find-LongFilePath -Path C:\dev\repos\client\backend | Export-Csv long-paths.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [string]$Path = '.',

        [ValidateRange(1, 32767)]
        [int]$MinimumLength = 250
    )

    $root = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    if ($root.StartsWith('\\?\')) {
        $searchRoot = $root
    }
    elseif ($root.StartsWith('\\')) {
        $searchRoot = '\\?\UNC\' + $root.Substring(2)
    }
    else {
        $searchRoot = '\\?\' + $root
    }

    Get-ChildItem -LiteralPath $searchRoot -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $fullName = $_.FullName -replace '^\\\\\?\\UNC\\', '\\' -replace '^\\\\\?\\', ''
        if ($fullName.Length -ge $MinimumLength) {
            [pscustomobject]@{
                Length = $fullName.Length
                Path   = $fullName
            }
        }
    } | Sort-Object -Property Length -Descending
}
