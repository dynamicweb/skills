<#
.SYNOPSIS
    WRITES: a new Integration Framework job file, copied from a working one
    with its mapping uids re-minted. Dry run by default; -Apply writes.

.DESCRIPTION
    An activity on 10.28.x is a FILE, not a database row, and there is no
    activity table to write — so copying an activity is a file operation and
    this is the enforced form of it.

    The sequence, and every step exists because skipping it fails silently:
      1. Copy a job that already WORKS, never a template. The working file
         carries the element shapes, the provider node names and the <Schema>
         snapshot a template does not.
      2. Decode with a utf16le decoder, edit the string, encode back with a
         utf16le encoder. A job file is UTF-16LE WITH a BOM (first two bytes
         FF FE) and its declaration says encoding="utf-16". Every scripting
         stack writes UTF-8 by default, so a UTF-8 "job file" is simply not a
         job and the runner will not read it. This script REFUSES a source
         that is not UTF-16LE rather than producing one.
      3. Round-trip: the bytes written are decoded again and compared against
         the string that was meant to be written, before anything runs.
      4. Diff the decoded copy against the decoded source, so a 36 KB or
         418 KB file is proven to differ in exactly the intended lines.
      5. Re-mint every <mapping uid="..."> GUID. A copy inherits them, and two
         live jobs sharing one mapping uid is a collision waiting to happen.
      6. Never grep a job file raw — the UTF-16 bytes hide what you search
         for and the result is a FALSE CLEAN. Every search here runs on the
         decoded string.

    Two things this script cannot decide, kept in the owning reference: the
    doubled `Files\Files` archive root (the destination folder is the jobs
    folder, `<wwwroot>/Files/Files/Integration/jobs/`, and a single-`Files`
    URL 404s), and that the file NAME is the activity name a scheduled task
    binds to.

    Owning reference: dw-data-access/references/recipes-integration.md
    ("Copy an integration activity between installs"); the file format itself
    is dw-integration-framework/references/job-file-format.md.

.PARAMETER SourcePath
    The working job file to copy. Must be UTF-16LE with a BOM.

.PARAMETER DestinationPath
    Where to write the copy. The file name before .xml becomes the activity
    name, so keep `&` out of it: the same string has to survive a filename and
    an XML attribute value.

.PARAMETER SetNode
    Element replacements applied to the decoded text, as @{ ElementName =
    'new value' }. Each replaces the text content of every <ElementName>...
    </ElementName> in the document. Use it to re-point a copy's
    SqlConnectionString, Server, Catalog, DestinationFolder or DestinationFile.
    An element the document does not contain is an error, not a no-op.

.PARAMETER KeepMappingUids
    Do not re-mint <mapping uid="...">. Only for a copy that replaces the
    source file at the same path.

.PARAMETER Apply
    Write the file. Without it nothing is written and the diff is printed.

.EXAMPLE
    pwsh -NoProfile -File scripts/Copy-DwIntegrationJob.ps1 -SourcePath "<wwwroot>/Files/Files/Integration/jobs/Orders export.xml" -DestinationPath "<wwwroot>/Files/Files/Integration/jobs/Orders export nightly.xml"

.EXAMPLE
    pwsh -NoProfile -File scripts/Copy-DwIntegrationJob.ps1 -SourcePath ./jobs/src.xml -DestinationPath ./jobs/dst.xml -SetNode @{ Catalog = 'TargetDb'; DestinationFolder = '/Files/Integration/outbox' } -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [hashtable]$SetNode,
    [switch]$KeepMappingUids,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

# A job file is UTF-16LE with a BOM. This encoder emits the BOM; the decoder
# below reads the bytes itself so the BOM can be asserted rather than assumed.
$utf16 = [System.Text.UnicodeEncoding]::new($false, $true)

function Read-JobText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "No such job file: $Path"
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 2 -or $bytes[0] -ne 0xFF -or $bytes[1] -ne 0xFE) {
        throw ("$Path does not start with the UTF-16LE BOM (FF FE). A job file is UTF-16LE with a " +
            "BOM and its declaration says encoding=`"utf-16`"; a UTF-8 file is not a job and the " +
            "runner will not read it. Re-export the source rather than converting this one blind.")
    }
    # Decode from after the BOM — the caller works on text, and the writer
    # re-emits the BOM itself.
    [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
}

function Get-DiffLines {
    param([string]$Before, [string]$After)
    $a = $Before -split "`r?`n"
    $b = $After -split "`r?`n"
    $out = [System.Collections.Generic.List[string]]::new()
    $max = [Math]::Max($a.Count, $b.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $left = if ($i -lt $a.Count) { $a[$i] } else { $null }
        $right = if ($i -lt $b.Count) { $b[$i] } else { $null }
        if ($left -ne $right) {
            if ($null -ne $left) { $out.Add(('  -{0,5}: {1}' -f ($i + 1), $left.Trim())) }
            if ($null -ne $right) { $out.Add(('  +{0,5}: {1}' -f ($i + 1), $right.Trim())) }
        }
    }
    $out
}

$source = Read-JobText -Path $SourcePath
$text = $source

# Step 5: re-mint every mapping uid. A copy inherits them.
$mintedCount = 0
if (-not $KeepMappingUids) {
    $text = [regex]::Replace($text, '(?i)(<mapping\b[^>]*?\buid=")([^"]*)(")', {
            param($m)
            $script:mintedCount++
            $m.Groups[1].Value + [guid]::NewGuid().ToString() + $m.Groups[3].Value
        })
    $mintedCount = $script:mintedCount
}

# Element re-pointing. Every named element must exist, or the copy silently
# keeps the source's connection / folder and runs against the wrong target.
if ($SetNode) {
    foreach ($name in $SetNode.Keys) {
        if ($name -notmatch '^[A-Za-z_][\w.-]*$') {
            throw "-SetNode key '$name' is not an XML element name."
        }
        $pattern = "(?s)(<$name(?:\s[^>]*)?>)(.*?)(</$name>)"
        $selfClosing = "<$name\s*/>"
        $hits = [regex]::Matches($text, $pattern).Count
        $empties = [regex]::Matches($text, $selfClosing).Count
        if ($hits -eq 0 -and $empties -eq 0) {
            throw ("The job carries no <$name> element. Read the node names off the file rather " +
                "than off the parameter labels: SqlProvider's AddInParameter names (SourceServer, " +
                "SourceDatabase, SourceConnectionString...) are UI aliases that the XmlNode " +
                "constructor ignores with no warning.")
        }
        $value = [System.Security.SecurityElement]::Escape([string]$SetNode[$name])
        if ($hits -gt 0) {
            $text = [regex]::Replace($text, $pattern, { param($m) $m.Groups[1].Value + $value + $m.Groups[3].Value })
        }
        if ($empties -gt 0) {
            $text = [regex]::Replace($text, $selfClosing, "<$name>$value</$name>")
        }
        Write-Host "  <$name> set on $($hits + $empties) node(s)."
    }
}

# Prove the result is still a document before writing it anywhere.
try { [xml]$text | Out-Null }
catch { throw "The edited job is not well-formed XML: $($_.Exception.Message)" }

Write-Host ''
Write-Host "Source:      $SourcePath"
Write-Host "Destination: $DestinationPath"
Write-Host ("Mapping uids re-minted: {0}" -f $(if ($KeepMappingUids) { 'SKIPPED (-KeepMappingUids)' } else { $mintedCount }))
if (-not $KeepMappingUids -and $mintedCount -eq 0) {
    Write-Host '  NOTE: no <mapping uid="..."> found. Confirm this file really is the activity you meant to copy.'
}

Write-Host ''
Write-Host 'Diff (decoded source vs decoded copy):'
$diff = Get-DiffLines -Before $source -After $text
if ($diff.Count -eq 0) {
    Write-Host '  (identical)'
}
else {
    $shown = 0
    foreach ($line in $diff) {
        if ($shown -ge 80) { Write-Host ('  ... {0} more differing line(s)' -f ($diff.Count - $shown)); break }
        Write-Host $line
        $shown++
    }
}

# The reference's exposure rule, checked on the DECODED text so the UTF-16
# bytes cannot produce a false clean.
if ([regex]::IsMatch($text, '(?i)\b(?:password|pwd)\s*=\s*[^;"<\s]')) {
    Write-Host ''
    Write-Host 'WARNING: the copy carries a credential in a connection node. Job files answer HTTP 200'
    Write-Host '  anonymously (.xml is not on the static-file blocklist) and DW re-serializes the job on'
    Write-Host '  every run, so a one-off hand edit does not hold. Use integrated security instead:'
    Write-Host '  <SourceServerSSPI> / <DestinationServerSSPI> beside <Server> / <Catalog>.'
}

if (-not $Apply) {
    Write-Host ''
    Write-Host 'DRY RUN — nothing written. Re-run with -Apply.'
    exit 0
}

if (Test-Path -LiteralPath $DestinationPath) {
    throw ("$DestinationPath already exists. The file name IS the activity name; overwriting one " +
        "activity with another is never what a copy means. Delete it deliberately first.")
}
if (-not $PSCmdlet.ShouldProcess($DestinationPath, 'write the copied job file (UTF-16LE with BOM)')) {
    exit 0
}

$parent = Split-Path -Parent $DestinationPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
[System.IO.File]::WriteAllBytes($DestinationPath, $utf16.GetPreamble() + $utf16.GetBytes($text))

# Step 3: round-trip. Read the bytes back and compare with what was meant.
$roundTripped = Read-JobText -Path $DestinationPath
if ($roundTripped -ne $text) {
    Write-Host 'FAILED: the round-tripped file does not decode back to what was written. The copy is not trustworthy.'
    exit 1
}
Write-Host ''
Write-Host "Wrote $DestinationPath — round-trip decode matches, BOM intact."
Write-Host 'The activity name is the file name. Validate the copy with Test-DwJobSchema.ps1 before running it.'
exit 0
