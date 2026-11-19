<#
.SYNOPSIS
WRITES: one local input file (the brand section of a recipe input). Converts a brand kit's swift2 folder into the input of the content.design-styles recipe.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. Reads the swift2 folder a brand kit extractor writes (ColorSchemes/<slug>.json, Typography/<slug>.json, Buttons/<slug>.json, Fonts/*.json with their files, branding/ files, logo-fields.json, area.json) and writes the recipe input's brand section: the MCP style tools' camelCase members, enums by name (font weight 100-900 to Thin-Black, text transform 0-3 to None-Capitalize, button shape 0-2 to Squared-Rounded-Pill), and every file uploaded to /Files/Images/<AssetFolder>, the one archive folder the MCP upload writes, with the fonts' and logos' paths pointed there. File paths in the output are relative to the output file. With an existing -OutPath the other sections are kept and brand is replaced. No target, no network.
.PARAMETER KitPath
The kit's swift2 folder.
.PARAMETER OutPath
The recipe input file to write; created when absent.
.PARAMETER AssetFolder
Folder under /Files/Images for the kit's files; default the kit slug.
.PARAMETER RenderCheck
Storefront paths that must still answer 200 after the re-skin, such as /en-us/home. A list, or one comma-separated text: through pwsh -File a list arrives as one argument, so "/a,/b" and "'/a','/b'" are split here.
.PARAMETER LogoWidth
LogoWidth written on the desktop header and footer logos; default 210, the kit sheet's desktop logo clamp. A slot in logo-fields.json that names its own Width keeps it.
.PARAMETER MobileLogoWidth
LogoWidth written on the mobile header and footer logos; default 150, the kit sheet's clamp below md, so the mobile header keeps room for its links.
.EXAMPLE
pwsh -NoProfile -File scripts/ConvertFrom-DwBrandKit.ps1 -KitPath ./brand-kit/acme/swift2 -OutPath ./recipe-input.json -RenderCheck /en-us/home
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$KitPath,
    [Parameter(Mandatory)][string]$OutPath,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*$')][string]$AssetFolder,
    [string[]]$RenderCheck = @(),
    [ValidateRange(16, 1200)][int]$LogoWidth = 210,
    [ValidateRange(16, 1200)][int]$MobileLogoWidth = 150
)
$ErrorActionPreference = 'Stop'
$kit = (Resolve-Path -LiteralPath $KitPath).Path
$out = [IO.Path]::GetFullPath($OutPath)
$outDir = Split-Path -Parent $out
function Read-KitJson([string]$Path) { ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw) -AsHashtable }
function Get-KitOne([string]$Folder) {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $kit $Folder) -Filter '*.json' -File -ErrorAction SilentlyContinue)
    if ($files.Count -ne 1) { throw "The kit has $($files.Count) style files in $Folder; expected one." }
    return Read-KitJson $files[0].FullName
}
$weights = @{100 = 'Thin'; 200 = 'ExtraLight'; 300 = 'Light'; 400 = 'Regular'; 500 = 'Medium'; 600 = 'SemiBold'; 700 = 'Bold'; 800 = 'ExtraBold'; 900 = 'Black'}
$transforms = @('None', 'Uppercase', 'Lowercase', 'Capitalize')
$shapes = @('Squared', 'Rounded', 'Pill')
function ConvertTo-KitEnum($Value, $Names, [string]$What) {
    # A name passes through; a number is the stored model's enum value.
    if ($null -eq $Value -or $Value -is [string]) { return $Value }
    $n = [int]$Value
    $name = if ($Names -is [hashtable]) { $Names[$n] } elseif ($n -ge 0 -and $n -lt $Names.Count) { $Names[$n] }
    if (-not $name) { throw "The kit's $What value $n has no name." }
    return $name
}
function Get-RelativePath([string]$Full) { [IO.Path]::GetRelativePath($outDir, $Full).Replace('\', '/') }
function Get-KitImageSize([string]$Path) {
    # Pixel width and height of a PNG, GIF, JPEG or SVG (width/height or viewBox), else $null. No image library.
    $bytes = [IO.File]::ReadAllBytes($Path)
    $be = { param($i, $n) $v = 0; for ($k = 0; $k -lt $n; $k++) { $v = $v * 256 + $bytes[$i + $k] }; $v }
    if ($bytes.Length -ge 24 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50) { return @((& $be 16 4), (& $be 20 4)) }
    if ($bytes.Length -ge 10 -and $bytes[0] -eq 0x47 -and $bytes[1] -eq 0x49) { return @(($bytes[6] + 256 * $bytes[7]), ($bytes[8] + 256 * $bytes[9])) }
    if ($bytes.Length -ge 4 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) {
        $i = 2
        while ($i + 9 -lt $bytes.Length -and $bytes[$i] -eq 0xFF) {
            $marker = $bytes[$i + 1]
            if ($marker -in 0xC0, 0xC1, 0xC2) { return @((& $be ($i + 7) 2), (& $be ($i + 5) 2)) }
            $i += 2 + (& $be ($i + 2) 2)
        }
        return $null
    }
    $text = [Text.Encoding]::UTF8.GetString($bytes, 0, [Math]::Min($bytes.Length, 4096))
    if ($text -match '<svg\b[^>]*>') {
        $tag = $Matches[0]
        if ($tag -match '\bwidth="(\d+(\.\d+)?)(px)?"' ) { $w = [double]$Matches[1]; if ($tag -match '\bheight="(\d+(\.\d+)?)(px)?"') { return @($w, [double]$Matches[1]) } }
        if ($tag -match '\bviewBox="\s*[-\d.]+[\s,]+[-\d.]+[\s,]+([\d.]+)[\s,]+([\d.]+)\s*"') { return @([double]$Matches[1], [double]$Matches[2]) }
    }
    return $null
}
function Test-KitLogo([string]$Slot, [string]$Name) {
    # A warning, not a refusal: a kit can rank a social-media icon or a favicon as a logo. The operator looks.
    $local = Join-Path (Join-Path $kit 'branding') $Name
    if (-not (Test-Path -LiteralPath $local)) { return }
    $size = Get-KitImageSize $local
    if (-not $size -or $size[0] -le 0 -or $size[1] -le 0) { return }
    $w = $size[0]; $h = $size[1]; $ratio = $w / $h
    $why = @()
    if ([Math]::Max($w, $h) -lt 100) { $why += "only $([int]$w)x$([int]$h) px, smaller than a plausible logo" }
    if ($ratio -ge 0.8 -and $ratio -le 1.25) { $why += "square ($([int]$w)x$([int]$h)), shaped like an icon rather than a wordmark" }
    if ($why.Count) { Write-Warning "logo slot ${Slot}: $Name is $($why -join ' and '); check that the kit ranked the brand logo here and not a social or app icon." }
}

$schemes = Get-KitOne 'ColorSchemes'
$typography = Get-KitOne 'Typography'
$button = Get-KitOne 'Buttons'
$slug = [string]$schemes.Id
if (-not $AssetFolder) { $AssetFolder = $slug }
$archive = "/Files/Images/$AssetFolder"
$brand = [ordered]@{id = $slug; name = [string]$schemes.Name}
$area = Join-Path $kit 'area.json'
if (Test-Path -LiteralPath $area) { $a = Read-KitJson $area; if ($a.saveAreas -and $a.saveAreas.ColorSchemeId) { $brand.defaultColorScheme = [string]$a.saveAreas.ColorSchemeId } }
$brand.colorSchemes = @(foreach ($s in $schemes.Schemes) {
    [ordered]@{id = $s.Id; name = $s.Name; backgroundColor = $s.BackgroundColor; foregroundColor = $s.ForegroundColor; primaryButtonColor = $s.PrimaryButtonColor; secondaryButtonColor = $s.SecondaryButtonColor}
})
$files = [Collections.Generic.List[object]]::new()
$fonts = [Collections.Generic.List[object]]::new()
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $kit 'Fonts') -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $font = Read-KitJson $f.FullName
    $name = Split-Path -Leaf ([string]$font.FilePath)
    $local = Join-Path $f.DirectoryName $name
    if (-not (Test-Path -LiteralPath $local)) { throw "Font $($font.Id) names $name, which is not beside it in the kit." }
    $files.Add([ordered]@{file = (Get-RelativePath $local); name = $name})
    $fonts.Add([ordered]@{id = $font.Id; name = $font.Name; family = $font.Family; filePath = "$archive/$name"; weight = (ConvertTo-KitEnum $font.Weight $weights 'font weight'); style = $(if ($font.Style) { $font.Style } else { 'normal' })})
}
foreach ($b in @(Get-ChildItem -LiteralPath (Join-Path $kit 'branding') -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $files.Add([ordered]@{file = (Get-RelativePath $b.FullName); name = $b.Name})
}
if ($files.Count) { $brand.assetFolder = $AssetFolder; $brand.files = $files.ToArray() }
if ($fonts.Count) { $brand.fonts = $fonts.ToArray() }
$t = [ordered]@{}
foreach ($k in @($typography.Keys)) {
    if ($k -in @('Id', 'Name') -or $null -eq $typography[$k]) { continue }
    $member = $k.Substring(0, 1).ToLowerInvariant() + $k.Substring(1)
    $value = switch -Wildcard ($k) {
        '*FontWeight' { ConvertTo-KitEnum $typography[$k] $weights $k }
        '*TextTransformation' { ConvertTo-KitEnum $typography[$k] $transforms $k }
        default { $typography[$k] }
    }
    # A custom font id wins over the family name, as the generated sheet does: the role names one or the other.
    if ($k -match '^(Paragraph|Heading|Button)Font$' -and $typography[$Matches[1] + 'CustomFontId']) { continue }
    $t[$member] = $value
}
$brand.typography = $t
$brand.buttonStyle = [ordered]@{shape = (ConvertTo-KitEnum $button.Shape $shapes 'button shape'); borderSize = $button.BorderSize; paddingX = $button.PaddingX; paddingY = $button.PaddingY}
$logos = Join-Path $kit 'logo-fields.json'
if (Test-Path -LiteralPath $logos) {
    $l = Read-KitJson $logos
    $toArchive = { param($p) if ($p) { "$archive/" + (Split-Path -Leaf ([string]$p)) } }
    if ($l.favicon) { $brand.favicon = & $toArchive $l.favicon }
    $slots = @{headerDesktop = 'HeaderDesktop'; headerMobile = 'HeaderMobile'; footerDesktop = 'FooterDesktop'; footerMobile = 'FooterMobile'}
    $layout = @(foreach ($k in @('headerDesktop', 'headerMobile', 'footerDesktop', 'footerMobile')) {
        $v = $l[$k]
        if ($null -eq $v) { continue }
        # A SelectedImage object names the path in Id; a file field takes the path as text.
        $path = if ($v -is [Collections.IDictionary]) { $v.Id } else { $v }
        $width = if ($v -is [Collections.IDictionary] -and $v.Width) { [string]$v.Width } elseif ($k -like '*Mobile') { [string]$MobileLogoWidth } else { [string]$LogoWidth }
        Test-KitLogo $slots[$k] (Split-Path -Leaf ([string]$path))
        [ordered]@{slot = $slots[$k]; logo = [ordered]@{Image = (& $toArchive $path); LogoName = $brand.name; LogoWidth = $width}}
    })
    if ($layout.Count) { $brand.layout = $layout }
}
# Through pwsh -File a list arrives as one text ("'/a','/b'"): split on commas and drop the quotes around each path.
$paths = @($RenderCheck | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim().Trim("'", '"').Trim() } | Where-Object { $_ })
foreach ($p in $paths) { if (-not $p.StartsWith('/')) { throw "RenderCheck path '$p' is not a storefront path starting with /." } }
if ($paths.Count) { $brand.renderCheck = @($paths | ForEach-Object { @{path = $_} }) }
$doc = if (Test-Path -LiteralPath $out) { Read-KitJson $out } else { [ordered]@{schema = 1} }
$doc['brand'] = $brand
[IO.File]::WriteAllText($out, ($doc | ConvertTo-Json -Depth 20) + "`n", [Text.UTF8Encoding]::new($false))
Write-Output "brand section written: $(@($brand.colorSchemes).Count) schemes, $($fonts.Count) fonts, $($files.Count) files, $(if ($brand.Contains('layout')) { @($brand.layout).Count } else { 0 }) logo slots"
