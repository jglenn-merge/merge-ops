# Expands .sln paths into the project files they reference. Project paths pass through as resolved full paths.
function Resolve-ProjectFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    foreach ($item in $Path) {
        $fullPath = (Resolve-Path -LiteralPath $item -ErrorAction Stop).ProviderPath

        if ([IO.Path]::GetExtension($fullPath) -ne '.sln') {
            $fullPath
            continue
        }

        $solutionDir = Split-Path -Parent $fullPath
        $pattern = '^Project\("\{[^}]+\}"\)\s*=\s*"[^"]*",\s*"([^"]+\.(?:cs|vb|fs)proj)"'
        $relativePaths = Select-String -LiteralPath $fullPath -Pattern $pattern | ForEach-Object { $_.Matches[0].Groups[1].Value }

        foreach ($relativePath in $relativePaths) {
            $projectPath = Join-Path $solutionDir $relativePath
            if (Test-Path -LiteralPath $projectPath) {
                (Resolve-Path -LiteralPath $projectPath).ProviderPath
            }
            else {
                Write-Warning "Project '$relativePath' listed in $fullPath was not found."
            }
        }
    }
}
