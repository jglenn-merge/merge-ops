# Removes a node along with the indentation whitespace in front of it, so the saved file has no blank gaps.
function Remove-XmlNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNode]$Node
    )

    $parent = $Node.ParentNode
    if (-not $parent) {
        return
    }

    $previous = $Node.PreviousSibling
    if ($previous -and $previous.NodeType -in @([System.Xml.XmlNodeType]::Whitespace, [System.Xml.XmlNodeType]::SignificantWhitespace)) {
        [void]$parent.RemoveChild($previous)
    }
    [void]$parent.RemoveChild($Node)
}
