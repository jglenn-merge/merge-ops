# Returns child folders newest first. CreationTime is the default because a folder's LastWriteTime changes whenever its contents do.
function Get-ChildFolderByAge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [ValidateSet('CreationTime', 'LastWriteTime')]
        [string]$Property = 'CreationTime'
    )

    Get-ChildItem -LiteralPath $Path -Directory | Sort-Object -Property $Property -Descending
}
