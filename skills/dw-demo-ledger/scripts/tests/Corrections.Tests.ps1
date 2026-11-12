<#
.SYNOPSIS
READ-ONLY. Red controls for the brand-build check corrections and inventory corrections.
.DESCRIPTION
PowerShell 7 and Pester. Owning reference: ../../references/contract.md. SQL controls run each
probe's own query against inline VALUES fixtures in tempdb on an explicit local server
(LEDGER_TEST_SQLSERVER); no database table is read and nothing is written. Without that variable
the SQL controls are skipped and every other control still runs.
.EXAMPLE
$env:LEDGER_TEST_SQLSERVER='.\SQLEXPRESS'; Invoke-Pester -Path scripts/tests/Corrections.Tests.ps1
#>
#Requires -Version 7.0
param()
BeforeDiscovery {
    $script:noSql=-not $env:LEDGER_TEST_SQLSERVER
    $script:versions=@('10.29.8','10.28.15')
}
BeforeAll {
    foreach($file in @('Ledger.Core.ps1','Ledger.Observations.ps1','Ledger.Sql.ps1','Pim.Fields.ps1','Ledger.Transport.ps1','Ledger.Execute.ps1')){. (Join-Path $PSScriptRoot "../$file")}
    $script:releases=Join-Path $PSScriptRoot '../../assets/releases'
    function Get-Probe([string]$Version,[string]$Path){Read-LedgerJson (Join-Path $releases "$Version/$Path") (Join-Path $releases '../check.schema.json')}
    function Get-Functions([string]$Version){
        $all=@{};foreach($f in Get-ChildItem (Join-Path $releases "$Version/functions") -Filter '*.json'){foreach($x in (Read-LedgerJson $f.FullName).functions){$all[$x.id]=$x}};$all
    }
    # Replace each named table after FROM or JOIN with an inline VALUES derived table, keeping its alias.
    function ConvertTo-FixtureSql([string]$Query,[hashtable]$Tables){
        foreach($name in $Tables.Keys){
            $t=$Tables[$name];$rows=(@($t.rows)|ForEach-Object {"($_)"}) -join ', '
            $derived="(SELECT * FROM (VALUES $rows) v($($t.columns -join ', '))$(if($t.empty){' WHERE 1 = 0'}))"
            $pattern="\b(FROM|JOIN)\s+$name\b(?:\s+(?!(?:WHERE|ON|JOIN|INNER|LEFT|RIGHT|CROSS|GROUP|ORDER|UNION)\b)([A-Za-z_]\w*))?"
            $Query=[regex]::Replace($Query,$pattern,{param($m) $alias=if($m.Groups[2].Success){$m.Groups[2].Value}else{$name};"$($m.Groups[1].Value) $derived $alias"}.GetNewClosure())
        }
        return $Query
    }
    function Invoke-ProbeFixture($Check,[hashtable]$Tables){
        $query=($Check.bindings|Where-Object {$_.id -eq 'local-sql'}).query
        $build=@{defaultLanguage='LANG1';productScope=@{exclude=@()}}
        $value=Invoke-Sqlcmd-Scalar -Server $env:LEDGER_TEST_SQLSERVER -Database 'tempdb' -Query (ConvertTo-FixtureSql (Expand-PimSql $query $build) $Tables)
        return @{value=$value;result=(Test-LedgerAssertion $Check.assertion @{value=$value;complete=$true})}
    }
    function T([string[]]$Columns,[string[]]$Rows,[switch]$Empty){@{columns=$Columns;rows=$Rows;empty=[bool]$Empty}}
    $script:product=@('ProductId','ProductLanguageId','ProductActive','ProductVariantId','ProductImageSmall','ProductImageMedium','ProductImageLarge')
    $script:detail=@('DetailProductId','DetailVariantId','DetailType','DetailIsDefault','DetailValue','DetailsGroupId','DetailLanguageId','DetailVersion','DetailsName')
    function P([string]$Id){"N'$Id', N'LANG1', 1, N'', N'', N'', N''"}
    function D([string]$Product,[string]$Value,[int]$Default=0,[int]$Group=1,[string]$Lang='',[string]$Version='',[string]$Name=''){
        "N'$Product', N'', 0, $Default, N'$Value', $Group, N'$Lang', N'$Version', N'$Name'"
    }
}
Describe 'Image checks count images, not documents (<_>)' -ForEach $versions {
    BeforeAll {$v=$_}
    It 'images-without-default ignores a document-only product and still fails an image without default' -Skip:$noSql {
        $c=Get-Probe $v 'probes/pim/images.images-without-default.json'
        $green=@{EcomProducts=(T $product @((P 'DOC'),(P 'IMG')));EcomDetails=(T $detail @((D 'DOC' '/Files/manual.pdf'),(D 'IMG' '/Files/a.jpg' 1),(D 'IMG' '/Files/b.pdf')))}
        (Invoke-ProbeFixture $c $green).result | Should -Be PASS
        $red=@{EcomProducts=(T $product @((P 'DOC'),(P 'IMG')));EcomDetails=(T $detail @((D 'DOC' '/Files/manual.pdf'),(D 'IMG' '/Files/a.jpg'),(D 'IMG' '/Files/b.pdf' 1)))}
        $r=Invoke-ProbeFixture $c $red;$r.value | Should -Be 1;$r.result | Should -Be FAIL
    }
    It 'image-share does not count a document as an image' -Skip:$noSql {
        $c=Get-Probe $v 'probes/pim/images.image-share.json'
        $docOnly=@{EcomProducts=(T $product @((P 'DOC')));EcomDetails=(T $detail @((D 'DOC' '/Files/manual.PDF')))}
        $r=Invoke-ProbeFixture $c $docOnly;$r.value | Should -Be 0;$r.result | Should -Be FAIL
        $half=@{EcomProducts=(T $product @((P 'DOC'),(P 'IMG')));EcomDetails=(T $detail @((D 'DOC' '/Files/manual.pdf'),(D 'IMG' '/Files/a.WebP')))}
        (Invoke-ProbeFixture $c $half).value | Should -Be 50
    }
}
Describe 'Field type spread counts global custom fields, never standard ones (<_>)' -ForEach $versions {
    It 'counts category and non-standard global types, text kinds once' -Skip:$noSql {
        $c=Get-Probe $_ 'probes/pim/field-types.type-spread.json'
        $t=@{EcomProductCategoryField=(T @('FieldCategoryId','FieldType') @("N'food', 1","N'food', 3","N'food', 15","N'reference_category', 9"))
             EcomProductField=(T @('ProductFieldTypeId','ProductFieldIsStandard') @("2, 0","7, 0","11, 0","4, 1","5, 1"))}
        (Invoke-ProbeFixture $c $t).value | Should -Be 5
        $t.EcomProductField=T @('ProductFieldTypeId','ProductFieldIsStandard') @("4, 1","5, 1")
        (Invoke-ProbeFixture $c $t).value | Should -Be 3
    }
}
Describe 'Stock checks accept stock held per location (<_>)' -ForEach $versions {
    It 'passes on a stock unit above zero and fails on zero or another variant' -Skip:$noSql {
        $c=Get-Probe $_ 'probes/commerce/stock-levels.in-stock.json'
        $p=T @('ProductId','ProductVariantId','ProductActive','ProductStock','ProductNeverOutOfStock') @("N'P1', N'', 1, 0, 0")
        $unit=@('StockUnitProductId','StockUnitVariantId','StockUnitQuantity','StockUnitNeverOutOfStock')
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomStockUnit=(T $unit @("N'P1', N'', 5, 0"))}).result | Should -Be PASS
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomStockUnit=(T $unit @("N'P1', N'', 0, 0"))}).result | Should -Be FAIL
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomStockUnit=(T $unit @("N'P1', N'V2', 5, 0"))}).result | Should -Be FAIL
    }
}
Describe 'Inventory corrections have green and red SQL controls (<_>)' -ForEach $versions {
    BeforeAll {$v=$_}
    It 'document-scope needs a different file per language in one category' -Skip:$noSql {
        $c=Get-Probe $v 'probes/pim/document-scope.language-assets.json';$p=T $product @((P 'G1'))
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomDetails=(T $detail @((D 'G1' '/Files/torr.pdf' 0 4 'LANG1'),(D 'G1' '/Files/mbar.pdf' 0 4 'LANG2')))}).result | Should -Be PASS
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomDetails=(T $detail @((D 'G1' '/Files/one.pdf' 0 4 'LANG1'),(D 'G1' '/Files/one.pdf' 0 4 'LANG2')))}).result | Should -Be FAIL
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomDetails=(T $detail @((D 'G1' '/Files/a.jpg' 0 4 'LANG1'),(D 'G1' '/Files/b.jpg' 0 4 'LANG2')))}).result | Should -Be FAIL
    }
    It 'document-metadata counts a versioned document, not a versioned image' -Skip:$noSql {
        $c=Get-Probe $v 'probes/pim/document-metadata.versioned.json';$p=T $product @((P 'G1'))
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomDetails=(T $detail @((D 'G1' '/Files/om.pdf' 0 4 '' '2025-04')))}).result | Should -Be PASS
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomDetails=(T $detail @((D 'G1' '/Files/om.pdf'),(D 'G1' '/Files/a.png' 0 1 '' '2025-04')))}).result | Should -Be FAIL
    }
    It 'alt text checks read the asset name and translated names' -Skip:$noSql {
        $p=T $product @((P 'G1'))
        $with=Get-Probe $v 'probes/pim/asset-alt-text.images-with-alt.json'
        $missing=Get-Probe $v 'probes/pim/asset-alt-text.missing-alt.json'
        $translated=Get-Probe $v 'probes/pim/asset-alt-text.translated.json'
        $good=@{EcomProducts=$p;EcomDetails=(T $detail @((D 'G1' '/Files/a.jpg' 1 1 'LANG1' '' 'Side view'),(D 'G1' '/Files/a.jpg' 1 1 'LANG2' '' 'Seitenansicht')))}
        foreach($c in @($with,$missing,$translated)){(Invoke-ProbeFixture $c $good).result | Should -Be PASS}
        $bad=@{EcomProducts=$p;EcomDetails=(T $detail @((D 'G1' '/Files/a.jpg' 1 1 'LANG1' '' 'Side view'),(D 'G1' '/Files/a.jpg' 1 1 'LANG2' '' 'Side view'),(D 'G1' '/Files/b.jpg')))}
        (Invoke-ProbeFixture $missing $bad).result | Should -Be FAIL
        (Invoke-ProbeFixture $translated $bad).result | Should -Be FAIL
        (Invoke-ProbeFixture $with @{EcomProducts=$p;EcomDetails=(T $detail @((D 'G1' '/Files/b.jpg'),(D 'G1' '/Files/c.pdf' 0 1 '' '' 'Manual')))}).result | Should -Be FAIL
    }
    It 'video files are counted by video extension only' -Skip:$noSql {
        $c=Get-Probe $v 'probes/pim/product-videos.video-files.json';$p=T $product @((P 'G1'))
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomDetails=(T $detail @((D 'G1' '/Files/Videos/demo.MP4')))}).result | Should -Be PASS
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomDetails=(T $detail @((D 'G1' '/Files/demo.pdf'),(D 'G1' '/Files/a.jpg')))}).result | Should -Be FAIL
    }
    It 'expected delivery is read on the product or its own stock unit' -Skip:$noSql {
        $c=Get-Probe $v 'probes/commerce/lead-times.stored.json'
        $p=T @('ProductId','ProductVariantId','ProductActive','ProductExpectedDelivery') @("N'P1', N'', 1, CAST(NULL AS datetime)")
        $unit=@('StockUnitProductId','StockUnitVariantId','StockUnitExpectedDelivery')
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomStockUnit=(T $unit @("N'P1', N'', CAST(N'2026-12-01' AS datetime)"))}).result | Should -Be PASS
        (Invoke-ProbeFixture $c @{EcomProducts=$p;EcomStockUnit=(T $unit @("N'P1', N'', CAST(NULL AS datetime)"))}).result | Should -Be FAIL
    }
    It 'reviews count rated product comments only' -Skip:$noSql {
        $c=Get-Probe $v 'probes/commerce/product-reviews.rated-comments.json'
        $p=T @('ProductId','ProductActive') @("N'P1', 1")
        $cols=@('CommentItemType','CommentItemId','CommentActive','CommentRating')
        (Invoke-ProbeFixture $c @{EcomProducts=$p;Comment=(T $cols @("N'ecomProduct', N'P1', 1, 4"))}).result | Should -Be PASS
        (Invoke-ProbeFixture $c @{EcomProducts=$p;Comment=(T $cols @("N'ecomProduct', N'P1', 1, 0","N'page', N'P1', 1, 5","N'ecomProduct', N'P1', 0, 5"))}).result | Should -Be FAIL
    }
    It 'delivery options need an active method with a product filter' -Skip:$noSql {
        $c=Get-Probe $v 'probes/orders/product-delivery-options.restricted-methods.json'
        $cols=@('ShippingActive','ShippingProductIds','ShippingProductGroupIds')
        (Invoke-ProbeFixture $c @{EcomShippings=(T $cols @("1, N'', N'GROUP1'"))}).result | Should -Be PASS
        (Invoke-ProbeFixture $c @{EcomShippings=(T $cols @("1, N'', N''","0, N'P1', N''"))}).result | Should -Be FAIL
    }
}
Describe 'Edit-layout and field-placement grounds and reads have SQL controls (<_>)' -ForEach $versions {
    BeforeAll {
        $v=$_
        function CatFields([string]$Category,[int]$Count){1..$Count|ForEach-Object {"N'$Category', N'f$_'"}}
        $script:catCols=@('FieldCategoryId','FieldId')
    }
    It 'one-attribute-family holds for one small family only' -Skip:$noSql {
        $c=Get-Probe $v 'probes/pim/screen-layouts.ruling.one-category-with-fields.json'
        $one=@{EcomProductCategoryField=(T $catCols (@(CatFields 'press' 25)+@(CatFields 'reference_category' 3)))}
        $r=Invoke-ProbeFixture $c $one;$r.value | Should -Be 1;$r.result | Should -Be PASS
        $r=Invoke-ProbeFixture $c @{EcomProductCategoryField=(T $catCols @(CatFields 'press' 26))};$r.value | Should -Be 2;$r.result | Should -Be FAIL
        (Invoke-ProbeFixture $c @{EcomProductCategoryField=(T $catCols (@(CatFields 'press' 3)+@(CatFields 'film' 3)))}).result | Should -Be FAIL
    }
    It 'single-family-catalogue holds for one category with fields, whatever its size' -Skip:$noSql {
        $c=Get-Probe $v 'probes/pim/field-placement.ruling.one-category-with-fields.json'
        (Invoke-ProbeFixture $c @{EcomProductCategoryField=(T $catCols (@(CatFields 'press' 40)+@(CatFields 'reference_category' 3)))}).result | Should -Be PASS
        (Invoke-ProbeFixture $c @{EcomProductCategoryField=(T $catCols (@(CatFields 'press' 2)+@(CatFields 'film' 1)))}).result | Should -Be FAIL
    }
    It 'the four layout reads run as local SELECTs and keep NULL parents and pipes intact' -Skip:$noSql {
        . (Join-Path $PSScriptRoot '../Pim.Layout.ps1')
        $tables=@{
            ScreenLayout=(T @('ScreenLayoutId','ScreenLayoutActive','ScreenLayoutScreenType','ScreenLayoutName') @("CAST(1 AS bigint), CAST(1 AS bit), N'Dynamicweb.Products.UI.Screens.ProductEditScreen', N'Editor'"))
            ScreenLayoutTab=(T @('ScreenLayoutTabId','ScreenLayoutTabScreenLayoutId','ScreenLayoutTabOrder','ScreenLayoutTabName') @("CAST(3 AS bigint), 1, 1, N'Press | heat'","CAST(4 AS bigint), CAST(NULL AS int), 2, N'Orphan'"))
            ScreenLayoutGroup=(T @('ScreenLayoutGroupId','ScreenLayoutGroupScreenLayoutTabId','ScreenLayoutGroupIsCatchAll','ScreenLayoutGroupOrder','ScreenLayoutGroupName') @("CAST(7 AS bigint), 3, CAST(1 AS bit), 1, N'Other fields '"))
            ScreenLayoutEditor=(T @('ScreenLayoutEditorId','ScreenLayoutEditorScreenLayoutGroupId','ScreenLayoutEditorOrder','ScreenLayoutEditorSystemName') @("CAST(9 AS bigint), N'7', 1, N'CategoryFields|ProductCategory|press|platen'"))
        }
        $real=${function:Invoke-Sqlcmd-Rows}
        Mock Invoke-Sqlcmd-Rows {& $real -Server $env:LEDGER_TEST_SQLSERVER -Database 'tempdb' -Query (ConvertTo-FixtureSql $Query $tables)}
        $l=Get-PimEditLayout -Server $env:LEDGER_TEST_SQLSERVER -Database 'tempdb'
        $l.tabs.name | Should -Contain 'Press | heat'
        ($l.tabs|Where-Object name -EQ 'Orphan').layoutId | Should -Be '0'
        $l.groups[0].name | Should -Be 'Other fields '
        $m=Resolve-PimEditLayout -Layout $l
        $m.tabs.Count | Should -Be 1
        $m.tabs[0].groups[0].catchAll | Should -BeTrue
        $m.tabs[0].groups[0].editors[0].field | Should -Be 'platen'
    }
}
Describe 'Declared attribute controls' {
    It 'accepts a range attribute on field type 16 only' {
        $a=@(@{category='c';field='f';kind='range'})
        @((Test-PimAttributeAspect -Aspect typing -Attribute $a -Stored @{'c|f'=@{type=16}}).offenders).Count | Should -Be 0
        @((Test-PimAttributeAspect -Aspect typing -Attribute $a -Stored @{'c|f'=@{type=7}}).offenders).Count | Should -Be 1
    }
    It 'counts an inherited default and still fails an attribute with neither value nor default' {
        $a=@(@{category='c';field='f';kind='text'})
        @((Test-PimAttributeAspect -Aspect values -Attribute $a -Stored @{'c|f'=@{values=0;defaults=1}}).offenders).Count | Should -Be 0
        @((Test-PimAttributeAspect -Aspect values -Attribute $a -Stored @{'c|f'=@{values=2;defaults=0}}).offenders).Count | Should -Be 0
        @((Test-PimAttributeAspect -Aspect values -Attribute $a -Stored @{'c|f'=@{values=0;defaults=0}}).offenders).Count | Should -Be 1
    }
}
Describe 'Item type table health counts mismatches only (<_>)' -ForEach $versions {
    It 'passes all healthy rows and fails the matching mismatch' {
        foreach($pair in @(@('probes/content/item-types.table-health.json','existsInSchema'),@('probes/content/item-types.table-health-metadata.json','existsInMeta'))){
            $c=Get-Probe $_ $pair[0];$b=$c.bindings|Where-Object {$_.surface -eq 'mcp'}
            $healthy=@(@{existsInSchema=$true;existsInMeta=$true},@{existsInSchema=$true;existsInMeta=$true})
            Test-LedgerAssertion $c.assertion (Measure-LedgerRows $healthy $b.projection) | Should -Be PASS
            $broken=@(@{existsInSchema=$true;existsInMeta=$true},@{existsInSchema=$true;existsInMeta=$true});$broken[1][$pair[1]]=$false
            Test-LedgerAssertion $c.assertion (Measure-LedgerRows $broken $b.projection) | Should -Be FAIL
            {Measure-LedgerRows @(@{name='x'}) $b.projection} | Should -Throw
        }
    }
}
Describe 'An authorisation refusal falls back; an observation never does' {
    BeforeEach {
        $script:check=Get-Probe '10.29.8' 'probes/pim/product-queries.shared-queries.json'
        $script:cap=@{mcp=@{available=$true;tools=@('list_files')};adminApi=@{authenticated=$false;queries=@()};dwapi=@{available=$false};file=@{available=$true;local=$true};sql=@{available=$false}}
    }
    It 'uses the local file binding after the MCP read is refused and names the refusal' {
        Mock Read-LedgerMcp {throw [UnauthorizedAccessException]::new('refused')}
        Mock Get-LedgerFileObservation {@{value=11;scanned=11;offenders=@();complete=$true}}
        $r=Invoke-LedgerCheck $check @{} $cap @{expectations=@{}} @('mcp','file') '' '' 'X:\Files'
        $r.result | Should -Be PASS;$r.surface | Should -Be file;$r.reason | Should -Match 'mcp-files'
    }
    It 'keeps a FAIL from the fallback binding' {
        Mock Read-LedgerMcp {throw [UnauthorizedAccessException]::new('refused')}
        Mock Get-LedgerFileObservation {@{value=0;scanned=0;offenders=@();complete=$true}}
        (Invoke-LedgerCheck $check @{} $cap @{expectations=@{}} @('mcp','file') '' '' 'X:\Files').result | Should -Be FAIL
    }
    It 'stays unverified when no other binding is available' {
        Mock Read-LedgerMcp {throw [UnauthorizedAccessException]::new('refused')}
        $cap.file.available=$false
        $r=Invoke-LedgerCheck $check @{} $cap @{expectations=@{}} @('mcp','file') '' '' ''
        $r.result | Should -Be UNVERIFIED;$r.reason | Should -Match 'not authorised'
    }
    It 'never retries a valid MCP observation on another surface' {
        Mock Read-LedgerMcp {@{data=@(@{path='/x';name='a.txt';isDirectory=$false})}}
        Mock Get-LedgerFileObservation {@{value=11;scanned=11;offenders=@();complete=$true}}
        $r=Invoke-LedgerCheck $check @{} $cap @{expectations=@{}} @('mcp','file') '' '' 'X:\Files'
        $r.result | Should -Be FAIL;$r.surface | Should -Be mcp
        Should -Invoke Get-LedgerFileObservation -Times 0
    }
}
Describe 'Snapshot contracts of the corrections (<_>)' -ForEach $versions {
    BeforeAll {$v=$_;$fs=Get-Functions $v}
    It 'no longer gates stored coordinates on an unknowable map credential' {
        @($fs['users.geolocation'].requires).Count | Should -Be 0
    }
    It 'offers the catalogue ground only with evidence and never on a core function' {
        $with=@($fs.Values|Where-Object {@($_.notApplicable.id) -contains 'catalogue-does-not-use'})
        $with.Count | Should -Be 25
        @($with.id|Where-Object {$_ -like 'pim.*' -or $_ -in @('orders.completed-orders','commerce.default-price')}).Count | Should -Be 0
    }
    It 'keeps every new correction unverified without a target' {
        $ids=if($v -eq '10.29.8'){@((Read-LedgerJson (Join-Path $releases '10.29.8/delta.json')).corrections.id)}else{@((Read-LedgerJson (Join-Path $releases '10.28.15/evidence/admission.json')).corrections.id)}
        $ids.Count | Should -BeGreaterThan 0
        foreach($id in $ids){
            $fs.ContainsKey($id) | Should -BeTrue
            foreach($path in $fs[$id].checks){
                $c=Get-Probe $v $path
                (Invoke-LedgerCheck $c @{} @{} @{expectations=@{}} @('mcp','admin-api','dwapi','file','sql') '' '' '').result | Should -Be UNVERIFIED
            }
        }
    }
}
