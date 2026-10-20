function ConvertFrom-IISLog {
    <#
    .SYNOPSIS
    Parses IIS W3C log files into objects.

    .DESCRIPTION
    Field names come from the log's #Fields: header, so custom field sets (such as an added X-Forwarded-For column) parse
    correctly. For log excerpts without a header, pass -Field or rely on the IIS default field list. Columns beyond the known
    fields are named Field<n>, where n is the zero-based column index.

    When the log has date and time fields, a Timestamp property (UTC) is added as the first property.

    .PARAMETER Path
    Log file paths. Wildcards are supported, and FileInfo objects can be piped in.

    .PARAMETER Field
    Field names to use instead of the #Fields: header.

    .EXAMPLE
    ConvertFrom-IISLog .\u_ex251015.log | Group-Object 'c-ip' | Sort-Object Count -Descending | Select-Object -First 10

    .EXAMPLE
    Get-ChildItem C:\inetpub\logs\LogFiles\W3SVC1 -Filter *.log | ConvertFrom-IISLog | Where-Object 'sc-status' -ge 500
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [string[]]$Field
    )

    begin {
        $defaultFields = @(
            'date', 'time', 's-ip', 'cs-method', 'cs-uri-stem', 'cs-uri-query', 's-port', 'cs-username', 'c-ip',
            'cs(User-Agent)', 'cs(Referer)', 'sc-status', 'sc-substatus', 'sc-win32-status', 'time-taken'
        )
        $culture = [Globalization.CultureInfo]::InvariantCulture
        $dateStyles = [Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal'
    }

    process {
        foreach ($item in $Path) {
            foreach ($resolved in (Resolve-Path -Path $item -ErrorAction Stop)) {
                if ($Field) {
                    $fields = $Field
                }
                else {
                    $fields = $defaultFields
                }

                $reader = New-Object System.IO.StreamReader($resolved.ProviderPath)
                try {
                    while ($null -ne ($line = $reader.ReadLine())) {
                        $line = $line.Trim()
                        if (-not $line) {
                            continue
                        }
                        if ($line.StartsWith('#')) {
                            if (-not $Field -and $line.StartsWith('#Fields:')) {
                                $fields = $line.Substring(8).Trim() -split '\s+'
                            }
                            continue
                        }

                        $values = $line -split ' '
                        $entry = [ordered]@{}
                        for ($i = 0; $i -lt $values.Count; $i++) {
                            if ($i -lt $fields.Count) {
                                $entry[$fields[$i]] = $values[$i]
                            }
                            else {
                                $entry["Field$i"] = $values[$i]
                            }
                        }

                        if ($entry.Contains('date') -and $entry.Contains('time')) {
                            $timestamp = [datetime]::MinValue
                            if ([datetime]::TryParseExact("$($entry['date']) $($entry['time'])", 'yyyy-MM-dd HH:mm:ss', $culture, $dateStyles, [ref]$timestamp)) {
                                $entry.Insert(0, 'Timestamp', $timestamp)
                            }
                        }

                        [pscustomobject]$entry
                    }
                }
                finally {
                    $reader.Dispose()
                }
            }
        }
    }
}
