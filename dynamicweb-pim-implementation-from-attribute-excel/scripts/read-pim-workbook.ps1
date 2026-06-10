param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string[]]$SheetNames = @("ProductGroups", "ProductAttributes")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

function Get-ColumnIndex {
    param([Parameter(Mandatory = $true)][string]$Letters)

    $sum = 0
    foreach ($ch in $Letters.ToCharArray()) {
        $sum = ($sum * 26) + ([int][char]$ch - [int][char]'A' + 1)
    }
    return $sum
}

function Get-SharedStrings {
    param([Parameter(Mandatory = $true)]$Zip)

    $entry = $Zip.Entries | Where-Object FullName -eq "xl/sharedStrings.xml"
    if (-not $entry) {
        return @()
    }

    $reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8, $true)
    try {
        $xml = [xml]$reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }

    $values = @()
    foreach ($si in $xml.sst.si) {
        # InnerText preserves the visible Excel text across plain and rich-text nodes.
        $values += [string]$si.InnerText
    }
    return $values
}

function Get-WorkbookRelations {
    param([Parameter(Mandatory = $true)]$Zip)

    $entry = $Zip.Entries | Where-Object FullName -eq "xl/_rels/workbook.xml.rels"
    $reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8, $true)
    try {
        $xml = [xml]$reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }

    $rels = @{}
    foreach ($rel in $xml.Relationships.Relationship) {
        $rels[[string]$rel.Id] = [string]$rel.Target
    }
    return $rels
}

function Get-WorkbookXml {
    param([Parameter(Mandatory = $true)]$Zip)

    $entry = $Zip.Entries | Where-Object FullName -eq "xl/workbook.xml"
    $reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8, $true)
    try {
        return [xml]$reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }
}

function Get-SheetRows {
    param(
        [Parameter(Mandatory = $true)]$Zip,
        [Parameter(Mandatory = $true)]$WorkbookXml,
        [Parameter(Mandatory = $true)]$Relations,
        [Parameter(Mandatory = $true)]$SharedStrings,
        [Parameter(Mandatory = $true)][string]$SheetName
    )

    $sheet = $WorkbookXml.workbook.sheets.sheet | Where-Object name -eq $SheetName
    if (-not $sheet) {
        throw "Sheet not found: $SheetName"
    }

    $target = $Relations[[string]$sheet.id]
    $sheetPath = "xl/" + $target.Replace("\", "/")
    $entry = $Zip.Entries | Where-Object FullName -eq $sheetPath
    $reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8, $true)
    try {
        $sheetXml = [xml]$reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }

    $rawRows = @()
    foreach ($row in $sheetXml.worksheet.sheetData.row) {
        $cells = @{}
        foreach ($cell in $row.c) {
            $ref = [string]$cell.r
            $colLetters = $ref -replace "\d", ""
            $colIndex = Get-ColumnIndex -Letters $colLetters
            $cellType = ""
            if ($cell.PSObject.Properties.Match("t").Count -gt 0) {
                $cellType = [string]$cell.t
            }

            $value = ""
            switch ($cellType) {
                "s" {
                    if ($cell.PSObject.Properties.Match("v").Count -gt 0) {
                        $index = [int]$cell.v
                        if ($index -lt $SharedStrings.Count) {
                            $value = [string]$SharedStrings[$index]
                        }
                    }
                }
                "inlineStr" {
                    if ($cell.PSObject.Properties.Match("is").Count -gt 0) {
                        $value = [string]$cell.is.InnerText
                    }
                }
                default {
                    if ($cell.PSObject.Properties.Match("v").Count -gt 0 -and $null -ne $cell.v) {
                        $value = [string]$cell.v
                    }
                }
            }

            $cells[$colIndex] = $value
        }
        $rawRows += $cells
    }

    if ($rawRows.Count -eq 0) {
        return @()
    }

    $maxColumn = 0
    foreach ($row in $rawRows) {
        foreach ($key in $row.Keys) {
            if ([int]$key -gt $maxColumn) {
                $maxColumn = [int]$key
            }
        }
    }

    $headers = @()
    for ($col = 1; $col -le $maxColumn; $col++) {
        $headers += [string]$rawRows[0][$col]
    }

    $rows = @()
    for ($rowIndex = 1; $rowIndex -lt $rawRows.Count; $rowIndex++) {
        $item = [ordered]@{
            RowNumber = $rowIndex + 1
        }

        for ($col = 1; $col -le $maxColumn; $col++) {
            $header = $headers[$col - 1]
            if ([string]::IsNullOrWhiteSpace($header)) {
                continue
            }
            $item[$header] = [string]$rawRows[$rowIndex][$col]
        }

        $rows += [pscustomobject]$item
    }

    return $rows
}

$fileStream = [System.IO.File]::Open(
    $Path,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::ReadWrite
)
$zip = [System.IO.Compression.ZipArchive]::new($fileStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
try {
    $workbookXml = Get-WorkbookXml -Zip $zip
    $relations = Get-WorkbookRelations -Zip $zip
    $sharedStrings = Get-SharedStrings -Zip $zip

    $output = [ordered]@{
        Path = (Resolve-Path $Path).Path
        Sheets = [ordered]@{}
    }

    foreach ($sheetName in $SheetNames) {
        $rows = Get-SheetRows -Zip $zip -WorkbookXml $workbookXml -Relations $relations -SharedStrings $sharedStrings -SheetName $sheetName
        $output.Sheets[$sheetName] = $rows
    }

    $output | ConvertTo-Json -Depth 10
}
finally {
    $zip.Dispose()
    $fileStream.Dispose()
}
