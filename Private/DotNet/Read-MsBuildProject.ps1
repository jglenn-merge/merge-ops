# Loads a project file with whitespace preserved so a later Save() keeps the original formatting.
function Read-MsBuildProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($Path)

    # XmlDocument is enumerable, so wrap it to stop the pipeline from unrolling its child nodes.
    return , $xml
}
