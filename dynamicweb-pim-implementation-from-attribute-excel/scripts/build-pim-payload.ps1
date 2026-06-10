param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-NoMojibake {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $suspectMarkers = @(
        [string][char]0xFFFD, # Unicode replacement character
        "Ã",
        "Â",
        "â"
    )

    foreach ($marker in $suspectMarkers) {
        if ($Value.Contains($marker)) {
            throw "Detected broken workbook text in ${Context}: '$Value'. Refusing to normalize corrupted input."
        }
    }
}

function ConvertFrom-CodePoints {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    $builder = New-Object System.Text.StringBuilder
    foreach ($codePoint in $CodePoints) {
        [void]$builder.Append([char]$codePoint)
    }
    return $builder.ToString()
}

function Normalize-MachineId {
    param([Parameter(Mandatory = $true)][string]$Value)

    Assert-NoMojibake -Value $Value -Context "Normalize-MachineId input"

    $normalized = $Value.Trim().ToLowerInvariant()

    $transliterations = @(
        @{ Source = [string][char]0x00E6; Target = "ae" },
        @{ Source = [string][char]0x00C6; Target = "ae" },
        @{ Source = [string][char]0x00F8; Target = "oe" },
        @{ Source = [string][char]0x00D8; Target = "oe" },
        @{ Source = [string][char]0x00E5; Target = "aa" },
        @{ Source = [string][char]0x00C5; Target = "aa" },
        @{ Source = [string][char]0x00E4; Target = "ae" },
        @{ Source = [string][char]0x00C4; Target = "ae" },
        @{ Source = [string][char]0x00F6; Target = "oe" },
        @{ Source = [string][char]0x00D6; Target = "oe" },
        @{ Source = [string][char]0x00FC; Target = "ue" },
        @{ Source = [string][char]0x00DC; Target = "ue" },
        @{ Source = [string][char]0x00DF; Target = "ss" },
        @{ Source = [string][char]0x1E9E; Target = "ss" }
    )

    foreach ($pair in $transliterations) {
        $normalized = $normalized.Replace($pair.Source, $pair.Target)
    }

    $decomposed = $normalized.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder
    foreach ($ch in $decomposed.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($ch)
        }
    }

    $normalized = $builder.ToString()
    $normalized = [regex]::Replace($normalized, "[^a-z0-9_]", "_")
    $normalized = [regex]::Replace($normalized, "_+", "_")

    if ($normalized.Length -gt 255) {
        $normalized = $normalized.Substring(0, 255)
    }

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "Normalize-MachineId produced an empty value for input: '$Value'"
    }

    return $normalized
}

function Assert-NormalizeMachineIdSelfTest {
    $cases = @(
        @{ Input = (ConvertFrom-CodePoints @(0x0056,0x00E6,0x0067,0x0074)); Expected = "vaegt" },
        @{ Input = (ConvertFrom-CodePoints @(0x0053,0x0074,0x00F8,0x0072,0x0072,0x0065,0x006C,0x0073,0x0065)); Expected = "stoerrelse" },
        @{ Input = (ConvertFrom-CodePoints @(0x0050,0x00E5,0x0062,0x0079,0x0067)); Expected = "paabyg" },
        @{ Input = (ConvertFrom-CodePoints @(0x004C,0x00E6,0x006B,0x0073,0x0074,0x0072,0x00F8,0x006D)); Expected = "laekstroem" },
        @{ Input = (ConvertFrom-CodePoints @(0x0044,0x0069,0x0061,0x006D,0x0065,0x0074,0x0065,0x0072,0x0020,0x0028,0x00F8,0x0029)); Expected = "diameter_oe_" },
        @{ Input = (ConvertFrom-CodePoints @(0x0053,0x0061,0x006E,0x0064,0x0062,0x006C,0x00E6,0x0073,0x0074)); Expected = "sandblaest" },
        @{ Input = (ConvertFrom-CodePoints @(0x0053,0x00F8,0x006C,0x0076)); Expected = "soelv" }
    )

    foreach ($case in $cases) {
        $actual = Normalize-MachineId -Value $case.Input
        if ($actual -ne $case.Expected) {
            throw "Normalize-MachineId self-test failed for '$($case.Input)'. Expected '$($case.Expected)' but got '$actual'."
        }
    }
}

function Split-ListOptions {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        $Value -split ";" |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function New-ListOption {
    param([Parameter(Mandatory = $true)][string]$Label)

    $machineKey = Normalize-MachineId -Value $Label

    return [pscustomobject]@{
        # Keep the Excel label human-readable and store the normalized key separately.
        Name  = $Label
        Value = $machineKey
    }
}

function Assert-ListOptionMapping {
    param([Parameter(Mandatory = $true)]$Option)

    if ([string]::IsNullOrWhiteSpace([string]$Option.Name)) {
        throw "List option Name must contain the original Excel label."
    }

    if ([string]::IsNullOrWhiteSpace([string]$Option.Value)) {
        throw "List option Value must contain the normalized machine key."
    }

    $expectedValue = Normalize-MachineId -Value ([string]$Option.Name)
    if ([string]$Option.Value -ne $expectedValue) {
        throw "List option mapping is invalid. Expected Value '$expectedValue' for Name '$($Option.Name)', but found '$($Option.Value)'."
    }
}

function Convert-ListOptions {
    param([string]$Value)

    $seen = @{}
    $result = @()

    foreach ($label in Split-ListOptions -Value $Value) {
        $machineKey = Normalize-MachineId -Value $label
        if ($seen.ContainsKey($machineKey)) {
            continue
        }

        $seen[$machineKey] = $true
        $option = New-ListOption -Label $label
        Assert-ListOptionMapping -Option $option
        $result += $option
    }

    return $result
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$readerPath = Join-Path $PSScriptRoot "read-pim-workbook.ps1"
Assert-NormalizeMachineIdSelfTest
$workbook = & $readerPath -Path $Path | ConvertFrom-Json

$attributes = @($workbook.Sheets.ProductAttributes)

$payload = [ordered]@{
    Path = $workbook.Path
    GlobalFields = @()
    CategoryFields = @()
}

foreach ($row in $attributes) {
    $fieldType = [string]$row.'Field Type'
    if ([string]::IsNullOrWhiteSpace($fieldType)) {
        continue
    }

    $mapped = [ordered]@{
        AttributeName   = [string]$row.'Attribute name'
        MachineId       = Normalize-MachineId -Value ([string]$row.'Attribute name')
        Scope           = $fieldType
        AttributeType   = [string]$row.'Attribute Type'
        Maintained      = [string]$row.Maintained
        PIMGroups       = [string]$row.'PIM Groups'
        ListboxOptions  = Convert-ListOptions -Value ([string]$row.'Listbox Options')
    }

    if ($fieldType -eq "GF") {
        $payload.GlobalFields += [pscustomobject]$mapped
        continue
    }

    if ($fieldType -eq "CF") {
        $payload.CategoryFields += [pscustomobject]$mapped
        continue
    }
}

$payload | ConvertTo-Json -Depth 10
