<#
.SYNOPSIS
WRITES: brand tokens, CSS, three paired Style models and assets in the host Files tree.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. Pure file generation. Seven scheme ids
stay stable; black/white button ink is selected by WCAG contrast. Sources are copied only.
.PARAMETER ConfigPath
Customer JSON.
.PARAMETER DemoRoot
Demo directory containing staged theme-default Files.
.PARAMETER Apply
Generate files; otherwise preview.
.EXAMPLE
pwsh -NoProfile -File scripts/New-DwBrandFiles.ps1 -ConfigPath $config -DemoRoot $demo -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$DemoRoot,[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
try {
    $c=Read-DwBuildConfig $ConfigPath; $p=Get-DwBuildPaths $DemoRoot; $b=$c.brand
    $custom=Join-Path $p.Files 'Templates/Designs/Swift-v2/Custom'
    $seed=Join-Path $p.Distribution 'layers/theme-default/files/Templates/Designs/Swift-v2/Custom/brand.tokens.json'
    $tokens=Get-Content -Raw $seed | ConvertFrom-Json -AsHashtable
    $defaults=@{primary='#15324F';secondary='#D9C8A5';accent='#D9C8A5';ink='#182B3A';background='#FFFFFF';radius='8px';fontFamily='Arial'}
    foreach($key in $defaults.Keys){if(-not $b[$key]){$b[$key]=$defaults[$key]}}
    $assets=@{}
    foreach($key in 'logo','favicon','appleTouchIcon','metaImage') { if($b[$key]){$assets[$key]=Resolve-DwBuildAsset $p.Root $b[$key]} }
    if($assets.logo -and [IO.Path]::GetExtension($assets.logo) -ne '.svg'){throw 'brand.logo must be SVG; other icons may be raster.'}
    if (-not $Apply -or -not $PSCmdlet.ShouldProcess($p.Files,'Generate customer brand files')) { Write-Host 'Plan: brand slot, seven schemes, typography/buttons pairs, copied source assets.'; exit 0 }
    $tokens.Remove('$comment'); $tokens.brand.name=$c.customer.name; $tokens.brand.logo.alt=$c.customer.name
    $tokens.css['--td-accent']=$b.accent; $tokens.css['--td-ink']=$b.ink; $tokens.css['--td-radius']=$b.radius
    $tokens.css['--td-ink-soft']=$b.ink; $tokens.css['--td-slate']=$b.primary
    $tokens.css['--td-grey-light']=$b.background
    foreach($scheme in $tokens.schemes) {
        $scheme.PrimaryButtonColor=$b.primary; $scheme.SecondaryButtonColor=$b.secondary; $scheme.AccentColor=$b.accent
        if($scheme.Id -in 'light','lightgrey1','lightgrey2'){$scheme.BackgroundColor=$b.background;$scheme.ForegroundColor=$b.ink}
        elseif($scheme.Id -eq 'secondary'){$scheme.BackgroundColor=$b.secondary;$scheme.ForegroundColor=Get-DwBuildInk $b.secondary}
        else{$scheme.BackgroundColor=$b.primary;$scheme.ForegroundColor=Get-DwBuildInk $b.primary}
        if($b.schemes -and $b.schemes.ContainsKey($scheme.Id)) {
            foreach($key in $b.schemes[$scheme.Id].Keys) {
                if($key -notin 'BackgroundColor','ForegroundColor','PrimaryButtonColor','SecondaryButtonColor','AccentColor' -or $b.schemes[$scheme.Id][$key] -notmatch '^#[0-9a-fA-F]{6}$'){throw "Invalid override for scheme $($scheme.Id)."}
                $scheme[$key]=$b.schemes[$scheme.Id][$key]
            }
        }
    }
    $tokens.typography.ParagraphFont=$b.fontFamily; $tokens.typography.HeadingFont=$b.fontFamily; $tokens.typography.ButtonFont=$b.fontFamily
    $tokens.typography.fontImport=$b.fontImportUrl; $tokens.buttons.borderRadius=$b.radius; $tokens.buttons.Shape=1
    $schemeModel=@{Name=$c.customer.name;Id='default';Schemes=@()}; $css=@()
    foreach($s in $tokens.schemes) {
        $model=@{GroupId='default';Name=$s.Name;Id=$s.Id;BackgroundColor=$s.BackgroundColor;ForegroundColor=$s.ForegroundColor;PrimaryButtonColor=$s.PrimaryButtonColor;SecondaryButtonColor=$s.SecondaryButtonColor;CustomColors=@(@{Id='accent';Name='accent';Color=$s.AccentColor},@{Id='accent-contrast';Name='accent-contrast';Color=(Get-DwBuildInk $s.AccentColor)})}
        $schemeModel.Schemes+=$model
        $css+=".dw-colorscheme-$($s.Id), [data-dw-colorscheme=`"$($s.Id)`"] {"
        foreach($pair in @(@('background',$s.BackgroundColor),@('foreground',$s.ForegroundColor),@('button-primary',$s.PrimaryButtonColor),@('button-secondary',$s.SecondaryButtonColor),@('accent',$s.AccentColor))) {
            $rgb=@(1,3,5 | ForEach-Object {[Convert]::ToInt32($pair[1].Substring($_,2),16)}) -join ', '
            $css+="--dw-color-$($pair[0]): $($pair[1]);"; $css+="--dw-color-$($pair[0])-rgb: $rgb;"
            if($pair[0] -notin 'background','foreground'){$css+="--dw-color-$($pair[0])-contrast: $(Get-DwBuildInk $pair[1]);"}
        }
        $css+='}'
    }
    $styles=Join-Path $p.Files 'System/Styles'
    Write-DwBuildJson (Join-Path $styles 'ColorSchemes/default.json') $schemeModel
    Set-Content (Join-Path $styles 'ColorSchemes/default.css') ($css -join "`n") -Encoding utf8NoBOM
    $ty=@{Id='default';Name=$c.customer.name};foreach($key in $tokens.typography.Keys){if($key -ne 'fontImport'){$ty[$key]=$tokens.typography[$key]}}
    Write-DwBuildJson (Join-Path $styles 'Typography/default.json') $ty
    $tyCss=Get-Content -Raw (Join-Path $p.Distribution 'layers/theme-default/files/System/Styles/Typography/default.css')
    $tyCss=$tyCss -replace '(?m)^@import[^;]+;',''; $tyCss=$tyCss.Replace('Inter',$b.fontFamily)
    if($b.fontImportUrl){$tyCss="@import url('$($b.fontImportUrl)');`n"+$tyCss}
    Set-Content (Join-Path $styles 'Typography/default.css') $tyCss -Encoding utf8NoBOM
    $buttons=@{Id='default';Name=$c.customer.name};foreach($key in 'Shape','BorderSize','PaddingY','PaddingX'){$buttons[$key]=$tokens.buttons[$key]}
    Write-DwBuildJson (Join-Path $styles 'Buttons/default.json') $buttons
    Set-Content (Join-Path $styles 'Buttons/default.css') ".dw-button, [data-dw-button] { --dw-btn-padding-x: $($buttons.PaddingX)rem; --dw-btn-padding-y: $($buttons.PaddingY)rem; --dw-btn-border-radius: $($b.radius); --dw-btn-border-width: $($buttons.BorderSize)px; }" -Encoding utf8NoBOM
    $brandDir=Join-Path $p.Files 'Images/Brand';New-Item -ItemType Directory -Force $brandDir | Out-Null
    if($assets.logo){Copy-Item -LiteralPath $assets.logo -Destination (Join-Path $brandDir 'logo.svg') -Force}
    else {
        $name=[System.Security.SecurityElement]::Escape($c.customer.name)
        "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"560`" height=`"64`" viewBox=`"0 0 560 64`"><text x=`"4`" y=`"44`" font-family=`"Arial,sans-serif`" font-size=`"30`" fill=`"$($b.primary)`">$name</text></svg>" | Set-Content (Join-Path $brandDir 'logo.svg') -Encoding utf8NoBOM
    }
    $customerDir=Join-Path $p.Files "Images/$($c.slug)"; New-Item -ItemType Directory -Force $customerDir | Out-Null
    $initials=(@($c.customer.name -split '\s+' | Where-Object {$_ -match '^[A-Za-z]'} | Select-Object -First 2 | ForEach-Object {$_.Substring(0,1).ToUpperInvariant()}) -join '')
    if(-not $initials){$initials=$c.slug.Substring(0,2).ToUpperInvariant()}
    foreach($key in 'favicon','appleTouchIcon','metaImage') {
        if($assets[$key]){$dest="$key$([IO.Path]::GetExtension($assets[$key]))";Copy-Item -LiteralPath $assets[$key] -Destination (Join-Path $customerDir $dest) -Force;$tokens.brand[$key]="/Files/Images/$($c.slug)/$dest"}
        else{
            $dest="$key.png";$title=if($key -eq 'metaImage'){$c.customer.name}else{$initials}
            $fontSize=if($key -eq 'metaImage'){32}else{160}
            New-DwBuildTile -Path (Join-Path $customerDir $dest) -Name $title -Fill $b.primary -FontSize $fontSize
            $tokens.brand[$key]="/Files/Images/$($c.slug)/$dest"
        }
    }
    $brandCss=@(':root:root {');foreach($key in @($tokens.css.Keys | Sort-Object)){$brandCss+="${key}: $($tokens.css[$key]);"};$brandCss+='}'
    Set-Content (Join-Path $custom 'brand.css') ($brandCss -join "`n") -Encoding utf8NoBOM
    Write-DwBuildJson (Join-Path $custom 'brand.tokens.json') $tokens
    Write-Host 'Generated brand slot and all three Style pairs; contrast measured for every button fill.'
    exit 0
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }
