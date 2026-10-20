function Find-WebExternalDomain {
    <#
    .SYNOPSIS
    Lists external domains referenced by script and stylesheet tags in a codebase.

    .DESCRIPTION
    Scans view and markup files for <script src> and <link href> tags that point to another host, and reports each domain with
    the files that reference it. The output is a starting point for a Content Security Policy or WAF allow list. It does not
    see URLs built in JavaScript or loaded by tag managers.

    .PARAMETER Path
    Root folder to scan.

    .PARAMETER Include
    File patterns to scan.

    .PARAMETER ExcludeDirectory
    Folder names to skip anywhere in the tree.

    .EXAMPLE
    Find-WebExternalDomain -Path C:\dev\repos\client-site\src | Export-Csv domains.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [string]$Path = '.',

        [string[]]$Include = @('*.aspx', '*.ascx', '*.html', '*.htm', '*.cshtml', '*.Master'),

        [string[]]$ExcludeDirectory = @('node_modules', 'bin', 'obj', '.git')
    )

    $root = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $pattern = '<(?:script|link)\b[^>]*?\b(?:src|href)\s*=\s*["''](?:https?:)?//([^/"''\s>:?#]+)'
    $domains = @{}

    $files = Get-ChildItem -Path $root -Recurse -File -Include $Include -ErrorAction SilentlyContinue | Where-Object {
        $relativeDir = $_.DirectoryName.Substring($root.Length)
        $segments = $relativeDir.Split([IO.Path]::DirectorySeparatorChar)
        -not ($segments | Where-Object { $ExcludeDirectory -contains $_ })
    }

    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        if (-not $content) {
            continue
        }

        foreach ($match in [regex]::Matches($content, $pattern, 'IgnoreCase')) {
            $domain = $match.Groups[1].Value.ToLowerInvariant()
            if (-not $domains.ContainsKey($domain)) {
                $domains[$domain] = [pscustomobject]@{
                    References = 0
                    Files      = New-Object System.Collections.Generic.HashSet[string]
                }
            }
            $domains[$domain].References++
            [void]$domains[$domain].Files.Add($file.FullName.Substring($root.Length).TrimStart('\', '/'))
        }
    }

    foreach ($domain in ($domains.Keys | Sort-Object)) {
        [pscustomobject]@{
            Domain     = $domain
            References = $domains[$domain].References
            Files      = @($domains[$domain].Files | Sort-Object)
        }
    }
}
