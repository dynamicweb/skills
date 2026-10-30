<#
.SYNOPSIS
WRITES: customer display content and stable-key catalogue values on a fresh local restore.
.DESCRIPTION
Owning reference: ../references/scripted-base-build.md. SQL is local installs only: no host or
Management API exists yet. All writes precede the first start, so no cached entity exists.
The whole rewrite is transactional, counts matched rows, and never changes stable keys.
.PARAMETER ConfigPath
Customer JSON with optional catalogue rename map.
.PARAMETER DemoRoot
Demo root containing restored database receipt and generated brand tokens.
.PARAMETER SqlServer
Local SQL Server with Windows authentication.
.PARAMETER Database
Database owned by this build.
.PARAMETER Apply
Write all planned changes. Dry run by default.
.EXAMPLE
pwsh -NoProfile -File scripts/Set-DwDemoBrandContent.ps1 -ConfigPath $config -DemoRoot $demo -SqlServer $server -Database $db -Apply
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$DemoRoot,[Parameter(Mandatory)][string]$SqlServer,[Parameter(Mandatory)][string]$Database,[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Dw.DemoBuild.psm1') -Force
try {
    $p=Get-DwBuildPaths $DemoRoot;$c=Read-DwBuildConfig $ConfigPath;$conn=Get-DwBuildConnection $SqlServer $Database
    $receipt=Get-Content -Raw (Join-Path $p.Notes 'database-owned.json') | ConvertFrom-Json
    if($receipt.database -ne $Database -or $receipt.server -ne $SqlServer){throw 'Database does not match the owned restore.'}
    $launch=Join-Path $p.Host 'Properties/launchSettings.json'
    $profile=Get-Content -Raw $launch | ConvertFrom-Json
    $port=([uri]$profile.profiles.'Dynamicweb.Host.Suite'.applicationUrl).Port
    if(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue){throw 'Brand content is pre-start only. Stop the owned host before applying this step.'}
    $plan=Get-DwBuildRenamePlan $c
    $vendorKept=Test-DwBuildVendorKept $c.customer.name
    $assets=@{};foreach($entry in $c.catalogue.products){if($entry.image){$assets[$entry.id]=Resolve-DwBuildAsset $p.Root $entry.image}}
    if(-not $Apply -or -not $PSCmdlet.ShouldProcess($Database,'Rewrite customer display values in one transaction')){Write-Host "Plan: company/content rewrite plus $($plan.Count) explicit catalogue field updates; stable keys preserved.";exit 0}
    $tiles=Get-DwBuildRows $conn "SELECT ProductId,ProductName,ProductImageSmall FROM EcomProducts WHERE ProductVariantId='' AND ProductId LIKE 'TCPROD%'"
    $secretPath=Join-Path $p.Notes 'build-secrets.local.json'
    $secrets=Get-Content -Raw $secretPath | ConvertFrom-Json -AsHashtable
    foreach($kind in 'api','mcp'){
        $key=$kind+'Token'
        if(-not $secrets[$key]){
            $value=[Environment]::GetEnvironmentVariable(('DW_'+$kind.ToUpperInvariant()+'_KEY_SECRET'))
            if(-not $value){$value=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()}
            if($value.Length -lt 32){throw 'API and MCP key secrets must be at least 32 characters.'}
            $secrets[$key]=@{api='DEMO';mcp='DEMOMCP'}[$kind]+'.'+$value
        }
    }
    Write-DwBuildJson $secretPath $secrets
    $cn=[System.Data.SqlClient.SqlConnection]::new($conn);$cn.Open();$tx=$cn.BeginTransaction();$counts=@{}
    function Update-Content([string]$Sql,[hashtable]$Values,[string]$Label,[int]$Minimum=1) {
        $cmd=$cn.CreateCommand();$cmd.Transaction=$tx;$cmd.CommandText=$Sql;$cmd.CommandTimeout=120
        foreach($key in $Values.Keys){$null=$cmd.Parameters.AddWithValue("@$key",$Values[$key])}
        $n=$cmd.ExecuteNonQuery();if($n -lt $Minimum){throw "$Label expected at least $Minimum rows, got $n."};$counts[$Label]=$n
    }
    try {
        Update-Content "DELETE FROM Area WHERE AreaName='Standard' AND NOT EXISTS (SELECT 1 FROM Page WHERE PageAreaID=AreaID)" @{} 'unusedStandardArea' 0
        $check=$cn.CreateCommand();$check.Transaction=$tx;$check.CommandText="SELECT COUNT(*) FROM Area WHERE AreaName='Standard'"
        if([int]$check.ExecuteScalar() -ne 0){throw 'Standard area contains pages. Clean it using the local scaffold recipe before continuing.'}
        Update-Content 'UPDATE Area SET AreaName=@name,AreaColorSchemeGroupId=@style,AreaButtonStyleId=@style,AreaTypographyId=@style WHERE AreaName<>@standard' @{name=$c.customer.name;style='default';standard='Standard'} 'area'
        Update-Content 'UPDATE EcomShops SET ShopName=@name WHERE ShopId=@shop' @{name=$c.customer.name;shop='SHOP1'} 'shop'
        # Rename the PIM shop and its generated field binding together, using an ASCII shop name.
        $pimStem=($c.customer.name -replace '[^A-Za-z0-9 ]','').Trim()
        if(-not $pimStem){$pimStem=$c.slug}
        $pimName=$pimStem+' PIM';$pimField='DATAMODEL_'+$pimName.Replace(' ','_')
        Update-Content 'UPDATE EcomShops SET ShopName=@name WHERE ShopId=@shop' @{name=$pimName;shop='TCSHOP-PIM'} 'pimShop'
        Update-Content 'UPDATE DynamicStructureLevels SET DynamicStructureLevelField=@field WHERE DynamicStructureLevelId=100171' @{field=$pimField} 'pimWorkspaceField'
        Update-Content 'UPDATE DynamicStructures SET DynamicStructureTitle=@name WHERE DynamicStructureUniqueId=(SELECT DynamicStructureLevelStructureId FROM DynamicStructureLevels WHERE DynamicStructureLevelId=100171)' @{name=$pimName+' - by data model'} 'pimWorkspaceTitle'
        $tables=Get-DwBuildRows $conn "SELECT t.name AS tbl,c.name AS col FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id JOIN sys.types ty ON ty.user_type_id=c.user_type_id WHERE ty.name IN ('nvarchar','varchar','ntext','text') AND (t.name LIKE 'ItemType[_]Swift%' OR t.name IN ('Page','Paragraph','EcomProducts','EcomGroups','EcomAssortments','EcomProductCategoryFieldValue','AccessUser','EcomOrders','EcomOrderLines','EcomDetails'))"
        foreach($row in $tables) {
            $table=$row.tbl;$col=$row.col
            $display=($table -like 'ItemType_*' -and $col -match '^(Title|Subtitle|Text|Name|AltText|MetaSiteName|Copyright|Description|Content|Label|Caption|FirstButton|SecondButton|ThirdButton)$') -or
                ($table -eq 'Page' -and $col -in 'PageMenuText','PageTitle','PageDescription','PageMetaTitle','PageMetaDescription') -or
                ($table -eq 'EcomAssortments' -and $col -eq 'AssortmentName') -or
                ($table -eq 'EcomProductCategoryFieldValue' -and $col -eq 'FieldValueValue') -or
                ($table -eq 'Paragraph' -and $col -eq 'ParagraphHeader') -or
                ($table -eq 'EcomProducts' -and $col -in 'ProductName','ProductShortDescription','ProductLongDescription','ProductMetaTitle','ProductMetaDescription') -or
                ($table -eq 'EcomGroups' -and $col -in 'GroupName','GroupDescription','GroupMetaTitle') -or
                ($table -eq 'AccessUser' -and $col -in 'AccessUserName','AccessUserCompany') -or
                ($table -eq 'EcomOrders' -and $col -match '^Order(Customer|Delivery)(Name|Company)$') -or
                ($table -eq 'EcomDetails' -and $col -in 'DetailsName','DetailsKeywords','DetailDescription') -or
                ($table -eq 'EcomOrderLines' -and $col -eq 'OrderLineProductName')
            if(-not $display -or $vendorKept){continue}
            foreach($old in 'Truvio Commerce','Truvio') {
                $sql="UPDATE [$table] SET [$col]=REPLACE(CAST([$col] AS nvarchar(max)),@old,@name) WHERE CAST([$col] AS nvarchar(max)) LIKE @pattern"
                Update-Content $sql @{old=$old;name=$c.customer.name;pattern="%$old%"} "$table.$col.$old" 0
            }
        }
        $token=Get-Content -Raw (Join-Path $p.Files 'Templates/Designs/Swift-v2/Custom/brand.tokens.json') | ConvertFrom-Json
        $master='ItemType_Swift-v2_Master';$logo='ItemType_Swift-v2_Logo'
        Update-Content "UPDATE [$master] SET CustomHeadInclude=@head,MetaSiteName=@name" @{head='/Files/Templates/Designs/Swift-v2/Custom/DefaultHeadInclude.cshtml';name=$c.customer.name} 'master'
        Update-Content "UPDATE [$logo] SET Image=@image,LogoName=@name" @{image='/Files/Images/Brand/logo.svg';name=$c.customer.name} 'logos'
        foreach($pair in @(@('Favicon','favicon'),@('AppleTouchIcon','appleTouchIcon'),@('MetaImage','metaImage'))) {
            if($token.brand.($pair[1])){Update-Content "UPDATE [$master] SET [$($pair[0])]=@value" @{value=$token.brand.($pair[1])} "master.$($pair[0])"}
        }
        # Copy keys are ParagraphHeader selectors, inspected by a dry run or an agent before use.
        foreach($section in $c.storefront.Keys) {
            $entry=$c.storefront[$section]
            if($entry -isnot [hashtable] -or -not $entry.paragraphHeader){throw "storefront.$section requires paragraphHeader and title/text fields."}
            foreach($field in $entry.Keys | Where-Object {$_ -ne 'paragraphHeader'}) {
                if($field -notin 'title','text','subtitle'){throw "Unsupported copy field: $field"}
                $col=@{title='Title';text='Text';subtitle='Subtitle'}[$field]
                Update-Content "UPDATE i SET [$col]=@value FROM [ItemType_Swift-v2_Text] i JOIN Paragraph p ON p.ParagraphItemId=i.Id AND p.ParagraphItemType='Swift-v2_Text' WHERE p.ParagraphHeader=@header" @{value=$entry[$field];header=$entry.paragraphHeader} "copy.$section.$field"
            }
        }
        foreach($persona in $c.personas) {
            if($persona.id -notin 100100,100101,100102,100103,100105,100106){throw 'Only existing sample account/persona ids can be rewritten.'}
            $map=@{name='AccessUserName';email='AccessUserEmail';company='AccessUserCompany';address='AccessUserAddress';zip='AccessUserZip';city='AccessUserCity';country='AccessUserCountryCode';phone='AccessUserPhone'}
            foreach($field in $persona.Keys | Where-Object {$_ -ne 'id'}) {
                if(-not $map.ContainsKey($field)){throw "Unsupported persona field: $field"}
                Update-Content "UPDATE AccessUser SET [$($map[$field])]=@value WHERE AccessUserID=@id" @{value=$persona[$field];id=$persona.id} "persona.$($persona.id).$field"
            }
        }
        foreach($step in $plan) {Update-Content $step.sql $step.parameters "$($step.table).$($step.key).$($step.column)"}
        foreach($entry in $c.catalogue.products) {
            if($entry.number) {
                Update-Content "UPDATE EcomProducts SET ProductNumber=@number+'-'+REPLACE(ProductVariantId,'.','-') WHERE ProductId=@id AND ProductVariantId<>''" @{number=$entry.number;id=$entry.id} "variants.$($entry.id)" 0
                Update-Content 'UPDATE EcomOrderLines SET OrderLineProductNumber=@number WHERE OrderLineProductId=@id' @{number=$entry.number;id=$entry.id} "orderNumbers.$($entry.id)" 0
            }
            if($entry.name){
                Update-Content "UPDATE EcomProducts SET ProductName=@name WHERE ProductId=@id AND ProductVariantId<>'' AND ProductLanguageId='ENU'" @{name=$entry.name;id=$entry.id} "variantNames.$($entry.id)" 0
                Update-Content 'UPDATE EcomOrderLines SET OrderLineProductName=@name WHERE OrderLineProductId=@id' @{name=$entry.name;id=$entry.id} "orderNames.$($entry.id)" 0
            }
            if($assets[$entry.id]) {
                $ext=[IO.Path]::GetExtension($assets[$entry.id]);if($ext -notin '.png','.jpg','.jpeg','.webp'){throw 'Product image must be PNG/JPEG/WebP.'}
                $image="/Files/Images/$($c.slug)/$($entry.id)$ext"
                Copy-Item -LiteralPath $assets[$entry.id] -Destination (Join-Path $p.Files "Images/$($c.slug)/$($entry.id)$ext") -Force
                Update-Content 'UPDATE EcomProducts SET ProductImageSmall=@image,ProductImageMedium=@image,ProductImageLarge=@image WHERE ProductId=@id' @{image=$image;id=$entry.id} "image.$($entry.id)"
                $oldImage=($tiles | Where-Object {$_.ProductId -eq $entry.id} | Select-Object -First 1).ProductImageSmall
                if($oldImage){Update-Content 'UPDATE EcomDetails SET DetailValue=@image WHERE DetailProductId=@id AND DetailValue=@old' @{image=$image;id=$entry.id;old=$oldImage} "primaryDetailImage.$($entry.id)" 0}
            }
        }
        # The shipped raster tiles have a vendor word in their source SVG. Replace those host
        # PNGs with neutral named tiles; never edit the Distribution or customer source files.
        foreach($tile in $tiles) {
            $url=$tile.ProductImageSmall
            if($url -notlike '/Files/Images/TruvioCommerce/products/*.png'){continue}
            $relative=$url.Substring('/Files/'.Length)
            $svg=Join-Path $p.Distribution ('layers/sample-data/files/'+[IO.Path]::ChangeExtension($relative,'.svg'))
            if(-not $vendorKept -and (Test-Path $svg) -and (Get-Content -Raw $svg) -match 'Truvio') {
                $name=$tile.ProductName.Replace('Truvio Commerce',$c.customer.name).Replace('Truvio',$c.customer.name)
                $override=@($c.catalogue.products | Where-Object id -eq $tile.ProductId | Select-Object -First 1)
                if($override.Count -and $override[0].name){$name=$override[0].name}
                New-DwBuildTile -Path (Join-Path $p.Files $relative) -Name $name
            }
        }
        $secrets.mcpConfigurationId=Initialize-DwBuildAccess -Connection $cn -Transaction $tx -ApiBearer $secrets.apiToken -McpBearer $secrets.mcpToken
        $counts['access.credentials']=3
        $tx.Commit()
    } catch { $tx.Rollback();throw } finally {$cn.Dispose()}
    Write-DwBuildJson (Join-Path $p.Notes 'content-rewrite.json') @{counts=$counts;stableKeys='preserved';pimShopName=$pimName;pimIndexField=$pimField}
    Write-DwBuildJson $secretPath $secrets
    Write-Host "Content committed: $($counts.Count) counted statements, $(($counts.Values | Measure-Object -Sum).Sum) matched rows."
    exit 0
} catch { Write-Error $_ -ErrorAction Continue;exit 1 }
