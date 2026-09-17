<#
.SYNOPSIS
    READ-ONLY. Validates an Integration Framework job file against the five
    faults that each fail at run time with a message pointing elsewhere.

.DESCRIPTION
    A job file carries a CACHED SNAPSHOT of each provider's view of its
    tables, taken when the job was authored or last saved, and never re-read
    at run time. The failures that follow all read as something else, so this
    script asserts them up front, on the DECODED text — a naive grep over a
    job file is a false clean, because the UTF-16 bytes hide what you search
    for.

    Checks, in order:
      1. ENCODING. UTF-16LE with a BOM (FF FE). A UTF-8 file is not a job.
      2. MAPPED COLUMN NOT IN SCHEMA. Every column a mapping names must be
         present in the <Schema> for that table. Source side: a column added
         after the job was saved is SILENTLY DROPPED — no error, no log line.
         Destination side: a hard refusal before a row is read,
         "Source table(<T>) has column mappings: <cols> that does not exists
         in the schema". Read that error as a stale snapshot first, not a
         mapping typo: the column usually does exist on the table.
      3. COLUMN ELEMENT SHAPE. SqlDestinationWriter casts every schema column
         to SqlColumn unconditionally, so a destination schema carrying the
         plain Dynamicweb.DataIntegration.Integration.Column throws
         InvalidCastException the moment writing starts. A SqlProvider SOURCE
         reader does not cast, so the same file reads fine and dies at the
         first write — which sends the investigation to the destination table,
         the mapping keys or the connection instead of to the element type.
      4. CONNECTION NODES. SqlProvider's AddInParameter names (SourceServer,
         SourceDatabase, SourceUsername, SourcePassword, SourceConnectionString
         and the Destination* twins) are UI ALIASES. The XmlNode constructor
         reads the backing property names, and anything serialized under an
         alias is ignored with no warning: a fully populated, completely inert
         source block is the natural first attempt. The failure signature is
         "The ConnectionString property has not been initialized", raised from
         BaseSqlReader..ctor or SqlProvider.RunJob — it reads like a platform
         defect and is a naming one. The empty-node fallback is
         DESTINATION-ONLY: a source resolves its own connection and has none.
      5. CREDENTIAL EXPOSURE. Job files answer HTTP 200 to an anonymous
         request (.xml is not on the static-file middleware's blocklist), and
         DW re-serializes the job on every run, so a one-off hand edit does
         not hold.

    What stays in the owning reference and is not machine-checkable here: the
    doubled `Files\Files` archive root, that `Files/System/Integration/Jobs/`
    is a decoy holding shipped quick-setup templates, and that
    `Job succeeded` means the rows were processed, not that the artefact you
    expected exists.

    Owning reference: dw-data-access/references/recipes-integration.md; the
    file format is dw-integration-framework/references/job-file-format.md.

.PARAMETER Path
    One or more job files, or a folder of them (the jobs folder is
    <wwwroot>/Files/Files/Integration/jobs/, note the doubled Files\Files).

.PARAMETER RequireIntegratedSecurity
    Fail, rather than warn, on a credential in a connection node.

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwJobSchema.ps1 -Path "<wwwroot>/Files/Files/Integration/jobs"

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-DwJobSchema.ps1 -Path ./jobs/Orders_export.xml -RequireIntegratedSecurity
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$Path,
    [switch]$RequireIntegratedSecurity
)

$ErrorActionPreference = 'Stop'

$SQL_COLUMN = 'Dynamicweb.DataIntegration.ProviderHelpers.SqlColumn'
$PLAIN_COLUMN = 'Dynamicweb.DataIntegration.Integration.Column'
# Serialized under these names, the value is read by nothing. The right-hand
# column is what the XmlNode constructor actually reads.
$ALIAS_NODES = [ordered]@{
    'SourceConnectionString'      = 'SqlConnectionString or ManualConnectionString'
    'DestinationConnectionString' = 'SqlConnectionString or ManualConnectionString'
    'SourceServer'                = 'Server'
    'DestinationServer'           = 'Server'
    'SourceDatabase'              = 'Catalog'
    'DestinationDatabase'         = 'Catalog'
    'SourceUsername'              = 'Username'
    'DestinationUsername'         = 'Username'
    'SourcePassword'              = 'Password'
    'DestinationPassword'         = 'Password'
}

$findings = [System.Collections.Generic.List[object]]::new()
function Add-Finding {
    param([string]$File, [ValidateSet('ERROR', 'WARN')][string]$Level, [string]$Message)
    $findings.Add([pscustomobject]@{ File = $File; Level = $Level; Message = $Message })
    Write-Host ('  {0,-5} {1}' -f $Level, $Message)
}

$files = [System.Collections.Generic.List[string]]::new()
foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p -PathType Container) {
        Get-ChildItem -LiteralPath $p -Filter *.xml -Recurse -File |
            ForEach-Object { $files.Add($_.FullName) }
    }
    elseif (Test-Path -LiteralPath $p -PathType Leaf) { $files.Add((Resolve-Path -LiteralPath $p).Path) }
    else { Write-Error "No such path: $p" -ErrorAction Continue; exit 1 }
}
if ($files.Count -eq 0) {
    Write-Error "No .xml job files under: $($Path -join ', ')" -ErrorAction Continue
    exit 1
}

$seenUids = @{}

foreach ($file in $files) {
    Write-Host ''
    Write-Host "== $file"

    # 1. Encoding, asserted on the bytes.
    $bytes = [System.IO.File]::ReadAllBytes($file)
    if ($bytes.Length -lt 2 -or $bytes[0] -ne 0xFF -or $bytes[1] -ne 0xFE) {
        Add-Finding -File $file -Level ERROR -Message (
            'not UTF-16LE with a BOM (FF FE) — a job file is UTF-16LE and the runner will not read ' +
            'a UTF-8 one. Every later check is skipped for this file.')
        continue
    }
    $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)

    try { $doc = [xml]$text }
    catch {
        Add-Finding -File $file -Level ERROR -Message "not well-formed XML: $($_.Exception.Message)"
        continue
    }

    # Schema tables, per side, by tableName.
    $schemaColumns = @{}   # "<side>/<table>" -> [string[]] column names
    $columnShapes = @{}    # "<side>/<table>" -> hashtable of type -> count
    foreach ($schema in $doc.SelectNodes('//Schema')) {
        $side = if ($schema.ParentNode) { $schema.ParentNode.Name } else { 'Unknown' }
        foreach ($table in $schema.SelectNodes('.//table')) {
            $tableName = $table.SelectSingleNode('tableName')
            if (-not $tableName) { continue }
            $key = "$side/$($tableName.InnerText)"
            $names = @($table.SelectNodes('.//column/name') | ForEach-Object { $_.InnerText })
            $schemaColumns[$key] = $names
            $shapes = @{}
            foreach ($col in $table.SelectNodes('.//column')) {
                $t = $col.GetAttribute('type')
                if (-not $t) { $t = '(no type attribute)' }
                $shapes[$t] = 1 + ($shapes[$t] ?? 0)
                if ($t -eq $SQL_COLUMN -and $col.GetAttribute('columnType') -ne $SQL_COLUMN) {
                    Add-Finding -File $file -Level ERROR -Message (
                        "$key column '$($col.SelectSingleNode('name').InnerText)' declares type=SqlColumn " +
                        'but not columnType=SqlColumn — the SqlColumn shape repeats the type on BOTH attributes.')
                }
            }
            $columnShapes[$key] = $shapes
        }
    }
    if ($schemaColumns.Count -eq 0) {
        Add-Finding -File $file -Level WARN -Message (
            'no <Schema> block. A SqlProvider job with none introspects the WHOLE database on first ' +
            'run and persists that snapshot into this file — a multi-megabyte document that then ' +
            'becomes the truth the mapping is validated against. Author a scoped schema.')
    }

    # 2. Every mapped column present in the schema for its table.
    foreach ($mapping in $doc.SelectNodes('//mapping')) {
        $sourceTable = $mapping.GetAttribute('sourceTableName')
        $destTable = $mapping.GetAttribute('destinationTableName')
        foreach ($pair in @(
                @{ Table = $sourceTable; Attr = 'sourceColumnName'; Side = 'source' },
                @{ Table = $destTable; Attr = 'destinationColumnName'; Side = 'destination' })) {
            if (-not $pair.Table) { continue }
            $key = @($schemaColumns.Keys | Where-Object { $_ -like "*/$($pair.Table)" }) | Select-Object -First 1
            if (-not $key) {
                Add-Finding -File $file -Level ERROR -Message (
                    "mapping $($pair.Side) table '$($pair.Table)' has no <table> in any <Schema>. On the " +
                    'destination side this is the "Destination table(s) not found in schema" refusal before ' +
                    'a row is read; on the source side the columns are silently dropped.')
                continue
            }
            foreach ($cm in $mapping.SelectNodes('.//columnMapping')) {
                $col = $cm.GetAttribute($pair.Attr)
                if (-not $col) { continue }
                if ($schemaColumns[$key] -notcontains $col) {
                    Add-Finding -File $file -Level ERROR -Message (
                        "mapped $($pair.Side) column '$($pair.Table).$col' is not in the <Schema> snapshot. " +
                        'Read this as a STALE snapshot first, not a mapping typo — the column usually does ' +
                        'exist on the table. Re-save through save_integration_activity_mapping, which reads ' +
                        'the live schema at save time.')
                }
            }
        }

        # 5b. mapping uid uniqueness, across every file in this run.
        $uid = $mapping.GetAttribute('uid')
        if ($uid) {
            if ($seenUids.ContainsKey($uid)) {
                Add-Finding -File $file -Level ERROR -Message (
                    "mapping uid $uid is also used by $($seenUids[$uid]) — a copied job inherits its " +
                    'mapping uids and two live jobs must not share one.')
            }
            else { $seenUids[$uid] = $file }
        }
    }

    # 3. Destination column element shape.
    $destinationIsSql = $text -match '(?i)SqlProvider' -and $doc.SelectNodes('//Destination').Count -gt 0
    foreach ($key in $columnShapes.Keys) {
        if ($key -notlike 'Destination/*') { continue }
        if (-not $destinationIsSql) { continue }
        $plain = $columnShapes[$key][$PLAIN_COLUMN]
        if ($plain) {
            Add-Finding -File $file -Level ERROR -Message (
                "$key carries $plain column(s) of the plain $PLAIN_COLUMN shape on a SQL-backed " +
                'destination. SqlDestinationWriter casts every schema column to SqlColumn ' +
                'unconditionally, so this throws InvalidCastException the moment writing starts, ' +
                'after the source has read fine.')
        }
    }

    # 4. Connection nodes.
    foreach ($alias in $ALIAS_NODES.Keys) {
        $node = $doc.SelectSingleNode("//$alias")
        if ($node -and $node.InnerText.Trim()) {
            Add-Finding -File $file -Level ERROR -Message (
                "<$alias> carries a value and is read by NOTHING — it is a UI alias. Write " +
                "<$($ALIAS_NODES[$alias])> instead. The failure signature is 'The ConnectionString " +
                "property has not been initialized' from BaseSqlReader..ctor or SqlProvider.RunJob.")
        }
    }
    $sourceNode = $doc.SelectSingleNode('//Source')
    if ($sourceNode -and $sourceNode.InnerXml -match '(?i)SqlProvider|SqlConnectionString') {
        $conn = $sourceNode.SelectSingleNode('.//SqlConnectionString')
        $manual = $sourceNode.SelectSingleNode('.//ManualConnectionString')
        $sspi = $sourceNode.SelectSingleNode('.//SourceServerSSPI')
        $hasConn = ($conn -and $conn.InnerText.Trim()) -or ($manual -and $manual.InnerText.Trim())
        $hasSspi = $sspi -and $sspi.InnerText.Trim() -match '(?i)true'
        if (-not $hasConn -and -not $hasSspi) {
            Add-Finding -File $file -Level ERROR -Message (
                'SqlProvider SOURCE with an empty connection node. The empty-node fallback is ' +
                'DESTINATION-ONLY: a destination picks up the site connection, a source resolves its ' +
                'own and has no default, so this job cannot start.')
        }
    }

    # 5. Credential exposure, on the decoded text.
    if ([regex]::IsMatch($text, '(?i)\b(?:password|pwd)\s*=\s*[^;"<\s]')) {
        $level = if ($RequireIntegratedSecurity) { 'ERROR' } else { 'WARN' }
        Add-Finding -File $file -Level $level -Message (
            'a credential is present in a connection node. This file answers HTTP 200 to an anonymous ' +
            'request (.xml is not on the static-file blocklist) and DW re-serializes the job on every ' +
            'run. Use <SourceServerSSPI> / <DestinationServerSSPI> beside <Server> / <Catalog>.')
    }

    if (-not ($findings | Where-Object { $_.File -eq $file })) { Write-Host '  OK' }
}

$errors = @($findings | Where-Object { $_.Level -eq 'ERROR' })
Write-Host ''
Write-Host ("{0} file(s): {1} error(s), {2} warning(s)." -f
    $files.Count, $errors.Count, @($findings | Where-Object { $_.Level -eq 'WARN' }).Count)
if ($errors.Count -gt 0) { exit 1 }
exit 0
