<#
.SYNOPSIS
READ-ONLY. Proves served pages, customer branding, personas, products, images and MCP readiness.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. Writes ignored evidence reports only.
Zero pages, zero product images or zero persona probes fail. Visible vendor text fails; stable
internal TC keys in URLs and CSS identifiers remain valid and are never treated as display copy.
.PARAMETER ConfigPath
Customer JSON used for the build.
.PARAMETER DemoRoot
Demo root holding local access secrets and receipts.
.EXAMPLE
pwsh -NoProfile -File scripts/Test-DwDemoBaseBuild.ps1 -ConfigPath $config -DemoRoot $demo
#>
#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$DemoRoot)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
try {
    $p=Get-DwBuildPaths $DemoRoot;$c=Read-DwBuildConfig $ConfigPath
    $r=Get-Content -Raw $p.Release | ConvertFrom-Json
    $launch=Get-Content -Raw (Join-Path $p.Host 'Properties/launchSettings.json') | ConvertFrom-Json
    $base=$launch.profiles.'Dynamicweb.Host.Suite'.applicationUrl
    if(-not ([uri]$base).IsLoopback){throw 'Acceptance accepts localhost or another loopback address only.'}
    $secretFile=Join-Path $p.Notes 'build-secrets.local.json';$secrets=Get-Content -Raw $secretFile | ConvertFrom-Json
    $ready=Join-Path $PSScriptRoot '../../dw-setup-install/scripts/Test-DwHostReady.ps1'
    if(-not(Test-Path $ready)){throw 'Complete presales bundle required: dw-setup-install is missing.'}
    $env:DW_MCP_TOKEN=$secrets.mcpToken
    Invoke-DwBuildCommand pwsh @('-NoProfile','-File',$ready,'-BaseUrl',$base,'-OutFile',(Join-Path $p.Notes 'host-readiness.md'))
    $db=Get-Content -Raw (Join-Path $p.Notes 'database-owned.json') | ConvertFrom-Json
    $conn=Get-DwBuildConnection $db.server $db.database
    foreach($expected in $r.editionModel.expectedCounts.PSObject.Properties){
        if($expected.Name -notin 'EcomProducts','EcomGroups','EcomCountries'){throw 'Edition declares an unsupported acceptance-count table.'}
        $count=Get-DwBuildRows $conn "SELECT COUNT(*) AS total FROM [$($expected.Name)]"
        if($count[0].total -ne $expected.Value){throw "Edition count mismatch for $($expected.Name): expected $($expected.Value), got $($count[0].total)."}
    }
    $pim=Get-DwBuildRows $conn "SELECT (SELECT COUNT(*) FROM EcomProducts WHERE ProductId LIKE 'TCPROD%') AS products,(SELECT COUNT(*) FROM EcomGroups WHERE GroupId LIKE 'TCDM-%') AS models,(SELECT COUNT(*) FROM EcomCompletionRules) AS completionRules,(SELECT COUNT(*) FROM DynamicStructures WHERE DynamicStructureUniqueId=(SELECT DynamicStructureLevelStructureId FROM DynamicStructureLevels WHERE DynamicStructureLevelId=100171)) AS workspaces"
    if($pim[0].products -lt 1 -or $pim[0].models -lt 4 -or $pim[0].completionRules -lt 1 -or $pim[0].workspaces -ne 1){throw 'The edition PIM setup is incomplete.'}
    $personas=Get-DwBuildRows $conn 'SELECT AccessUserID,AccessUserUserName,AccessUserName FROM AccessUser WHERE AccessUserID IN (100101,100102,100103)'
    if($personas.Count -ne 3){throw 'Three persona rows are required.'}
    # Friendly URLs carry the language prefix; the edition's critical paths already do.
    $lang=if($c.customer.language){$c.customer.language.ToLowerInvariant()}else{'en-us'}
    $pages=@(@($r.editionModel.criticalPaths)+@("/$lang/shop","/$lang/cart/","/$lang/customer-center","/$lang/sign-in/sign-in") | Select-Object -Unique)
    if(-not $pages.Count){throw 'Zero critical pages.'}
    $accounts=@($personas | ForEach-Object {@{role=[string]$_.AccessUserID;username=$_.AccessUserUserName;secretKey=[string]$_.AccessUserID;identityPath='/en-us/customer-center';identityContains=$_.AccessUserName}})
    $story=@{baseUrl=$base;pages=$pages;placeholderRegex=$(if(Test-DwBuildVendorKept $c.customer.name){'placeholder|lorem ipsum'}else{'\bTruvio\b|placeholder|lorem ipsum'});personas=@{login=@{path='/en-us/sign-in/sign-in';extraFields=@{LoginAction='Login'}};accounts=$accounts}}
    $storyPath=Join-Path $p.Notes 'storyline-config.json';Write-DwBuildJson $storyPath $story
    Invoke-DwBuildCommand pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Test-DwDemoStoryline.ps1'),'-ConfigPath',$storyPath,'-SecretsPath',$secretFile,'-OutFile',(Join-Path $p.Notes 'storyline-proof.json'))
    $homePage=Invoke-WebRequest -Uri "$base/en-us/home" -SkipCertificateCheck -TimeoutSec 120
    if([Net.WebUtility]::HtmlDecode([string]$homePage.Content) -notmatch [regex]::Escape($c.customer.name)){throw 'Home does not contain customer name.'}
    foreach($sheet in 'ColorSchemes/default.css','Buttons/default.css','Typography/default.css','Custom/default_custom.css','Custom/brand.css'){
        if($homePage.Content -notmatch [regex]::Escape($sheet)){throw "Home did not link $sheet."}
    }
    $brand=Invoke-WebRequest -Uri "$base/Files/Templates/Designs/Swift-v2/Custom/brand.css" -SkipCertificateCheck -TimeoutSec 60
    $tokens=Get-Content -Raw (Join-Path $p.Files 'Templates/Designs/Swift-v2/Custom/brand.tokens.json') | ConvertFrom-Json -AsHashtable
    foreach($key in $tokens.css.Keys){if($brand.Content -notmatch [regex]::Escape("${key}: $($tokens.css[$key]);")){throw "Served brand token mismatch: $key"}}
    $typography=Invoke-WebRequest -Uri "$base/Files/System/Styles/Typography/default.css" -SkipCertificateCheck -TimeoutSec 60
    Test-DwBuildTypographyCss -Css ([string]$typography.Content) -Font $tokens.typography.ParagraphFont
    $plp=Invoke-WebRequest -Uri "$base/en-us/shop" -SkipCertificateCheck -TimeoutSec 120
    $products=Get-DwBuildRows $conn "SELECT ProductName,ProductImageSmall FROM EcomProducts WHERE ProductVariantId='' AND ProductActive=1 AND ProductId LIKE 'TCPROD%'"
    $shown=@($products | Where-Object {$plp.Content -match [regex]::Escape([Net.WebUtility]::HtmlEncode($_.ProductName)) -or $plp.Content -match [regex]::Escape($_.ProductName)})
    if(-not $shown.Count){throw 'PLP lists zero named catalogue products.'}
    $images=0
    foreach($product in $shown | Select-Object -First 8){
        if(-not $product.ProductImageSmall){throw 'Shown product lacks an image.'}
        $image=Invoke-WebRequest -Uri ($base+$product.ProductImageSmall) -SkipCertificateCheck -TimeoutSec 60
        if($image.StatusCode -ne 200 -or [string]$image.Headers.'Content-Type' -notmatch 'image/'){throw 'Product image did not resolve as an image.'}
        $images++
    }
    if(-not $images){throw 'Zero images probed.'}
    Write-DwBuildJson (Join-Path $p.Notes 'acceptance.json') @{status='PASS';pages=$pages.Count;personas=3;namedProducts=$shown.Count;imageProbes=$images;brandTokens=$tokens.css.Count;pim=$pim[0]}
    Write-Host "PASS: $($pages.Count) pages, three personas, $($shown.Count) named products, $images images, brand tokens and MCP readiness."
    exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
