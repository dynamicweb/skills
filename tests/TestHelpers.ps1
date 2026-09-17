# Shared helpers for the hermetic script suites. Dot-sourced from each
# *.Tests.ps1 inside BeforeAll.

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function New-JobXml {
    <#
        Builds a minimal but structurally real Integration Framework job
        document. Every fault the validator looks for is reachable from a
        parameter so a test can produce exactly one of them.
    #>
    param(
        [string]$MappingUid = '11111111-1111-1111-1111-111111111111',
        [string]$SourceColumn = 'OrderId',
        [string]$DestinationColumn = 'OrderId',
        [string[]]$SourceSchemaColumns = @('OrderId'),
        [string[]]$DestinationSchemaColumns = @('OrderId'),
        [string]$DestinationColumnType = 'Dynamicweb.DataIntegration.ProviderHelpers.SqlColumn',
        [string]$SourceConnection = 'Server=.\SQLEXPRESS;Catalog=Dw;',
        [string]$AliasNodeName,
        [string]$AliasNodeValue = 'something',
        [switch]$EmptySourceConnection
    )
    $sqlType = 'Dynamicweb.DataIntegration.ProviderHelpers.SqlColumn'
    $srcCols = ($SourceSchemaColumns | ForEach-Object {
            "<column type=`"$sqlType`" columnType=`"$sqlType`"><name>$_</name><type>System.String</type><isNew>False</isNew><isPrimaryKey>False</isPrimaryKey></column>"
        }) -join ''
    $dstCols = ($DestinationSchemaColumns | ForEach-Object {
            $extra = if ($DestinationColumnType -eq $sqlType) { " columnType=`"$sqlType`"" } else { '' }
            "<column type=`"$DestinationColumnType`"$extra><name>$_</name><type>System.String</type><isNew>False</isNew><isPrimaryKey>False</isPrimaryKey></column>"
        }) -join ''
    $alias = if ($AliasNodeName) { "<$AliasNodeName>$AliasNodeValue</$AliasNodeName>" } else { '' }
    $conn = if ($EmptySourceConnection) { '<SqlConnectionString />' } else { "<SqlConnectionString>$SourceConnection</SqlConnectionString>" }
    @"
<?xml version="1.0" encoding="utf-16"?>
<Job>
  <Source type="Dynamicweb.DataIntegration.Providers.SqlProvider.SqlProvider">
    $conn
    $alias
    <Schema><table><tableName>Orders</tableName>$srcCols</table></Schema>
  </Source>
  <Destination type="Dynamicweb.DataIntegration.Providers.SqlProvider.SqlProvider">
    <SqlConnectionString>Server=.;Catalog=Target;</SqlConnectionString>
    <Schema><table><tableName>TargetOrders</tableName>$dstCols</table></Schema>
  </Destination>
  <Mappings>
    <mapping uid="$MappingUid" sourceTableName="Orders" destinationTableName="TargetOrders">
      <columnMappings>
        <columnMapping sourceColumnName="$SourceColumn" destinationColumnName="$DestinationColumn" />
      </columnMappings>
    </mapping>
  </Mappings>
</Job>
"@
}

function Write-Utf16Job {
    param([string]$Path, [string]$Text)
    $enc = [System.Text.UnicodeEncoding]::new($false, $true)
    [System.IO.File]::WriteAllBytes($Path, $enc.GetPreamble() + $enc.GetBytes($Text))
}

function Read-Utf16Job {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
}

function New-StubbedScript {
    <#
        Copies a script that imports Dw.Api.psm1 / Dw.Sql.Local.psm1 into an
        isolated folder beside recording stub modules of the same names, so the
        script's own $PSScriptRoot-relative Import-Module resolves to the stub.
        Returns the path of the copied script; the stubs append one line per
        call to the log file given, in the order they were called.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [string]$TasksResponseJson = '{"data":[]}',
        [string]$CachesResponseJson = '{"data":[]}',
        [switch]$FailFlush
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $copied = Join-Path $Destination (Split-Path -Leaf $ScriptPath)
    Copy-Item -LiteralPath $ScriptPath -Destination $copied -Force

    $api = @"
`$script:LogPath = '$($LogPath -replace "'", "''")'
function Write-StubLog([string]`$Line) { Add-Content -LiteralPath `$script:LogPath -Value `$Line }
function Connect-Dw { param(`$BaseUrl, `$ApiToken, `$McpToken, `$SqlConnection, `$SolutionPath, [switch]`$AllowSelfSignedCertificate) Write-StubLog 'Connect-Dw'; [pscustomobject]@{ BaseUrl = 'https://stub' } }
function Assert-DwConnection { Write-StubLog 'Assert-DwConnection'; `$true }
function Invoke-DwApi {
    param([Parameter(Mandatory = `$true)][string]`$Command, `$Body, [string]`$Method, [int]`$TimeoutSec = 120)
    Write-StubLog "Invoke-DwApi `$Command"
    if (`$Command -like 'Tasks*') { return ('$($TasksResponseJson -replace "'", "''")' | ConvertFrom-Json) }
    if (`$Command -like 'GetServiceCaches*') { return ('$($CachesResponseJson -replace "'", "''")' | ConvertFrom-Json) }
    [pscustomobject]@{ status = 'ok' }
}
function Clear-DwServiceCache {
    param([string[]]`$CacheTypeName, [switch]`$All)
    foreach (`$n in `$CacheTypeName) { Write-StubLog "Clear-DwServiceCache `$n" }
    if (`$$($FailFlush.IsPresent.ToString().ToLower())) { throw 'Cache storage type not found' }
}
Export-ModuleMember -Function Connect-Dw, Assert-DwConnection, Invoke-DwApi, Clear-DwServiceCache
"@
    Set-Content -LiteralPath (Join-Path $Destination 'Dw.Api.psm1') -Value $api -Encoding utf8NoBOM

    $sql = @"
`$script:LogPath = '$($LogPath -replace "'", "''")'
function Write-StubSqlLog([string]`$Line) { Add-Content -LiteralPath `$script:LogPath -Value `$Line }
function Invoke-DwSqlNonQuery {
    param([Parameter(Mandatory = `$true)][string]`$Sql, [hashtable]`$Parameters, [string]`$ConnectionString)
    Write-StubSqlLog "Invoke-DwSqlNonQuery `$(`$Sql -replace '\s+', ' ')"
    1
}
function Invoke-DwSqlScalarWrite {
    param([Parameter(Mandatory = `$true)][string]`$Sql, [hashtable]`$Parameters, [string]`$ConnectionString)
    Write-StubSqlLog "Invoke-DwSqlScalarWrite `$(`$Sql -replace '\s+', ' ')"
    if (`$Parameters) {
        foreach (`$k in (`$Parameters.Keys | Sort-Object)) {
            `$v = `$Parameters[`$k]
            `$shown = if (`$null -eq `$v) { 'NULL' } else { [string]`$v }
            Write-StubSqlLog "  param `$k=`$shown"
        }
    }
    4242
}
Export-ModuleMember -Function Invoke-DwSqlNonQuery, Invoke-DwSqlScalarWrite
"@
    Set-Content -LiteralPath (Join-Path $Destination 'Dw.Sql.Local.psm1') -Value $sql -Encoding utf8NoBOM
    $copied
}

function Get-StubLog {
    param([string]$LogPath)
    if (-not (Test-Path -LiteralPath $LogPath)) { return @() }
    @(Get-Content -LiteralPath $LogPath)
}

function New-StubbedApiScript {
    <#
        The config-driven sibling of New-StubbedScript, for the scripts that
        call Invoke-DwMcp / Invoke-DwApi / Get-DwSqlScalar. The stub reads a
        JSON config beside itself at run time, so no response shape has to be
        escaped into the generated module source. Every call is logged in
        order; MCP and API calls also log their arguments as compact JSON.

        Config keys, all optional:
          mcp        map of tool name -> response object
          api        map of command PREFIX -> response object
          sqlScalar  array of @{ match = '<substring>'; value = <scalar> }
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [hashtable]$Config = @{}
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $copied = Join-Path $Destination (Split-Path -Leaf $ScriptPath)
    Copy-Item -LiteralPath $ScriptPath -Destination $copied -Force
    $configPath = Join-Path $Destination 'stub-config.json'
    ($Config | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM

    $module = @'
$script:StubLog = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'stub-log-path.txt') -Raw).Trim()
$script:StubConfig = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'stub-config.json') -Raw | ConvertFrom-Json
function Write-StubLine([string]$Line) { Add-Content -LiteralPath $script:StubLog -Value $Line }
function Connect-Dw { param($BaseUrl, $ApiToken, $McpToken, $SqlConnection, $SolutionPath, [switch]$AllowSelfSignedCertificate) Write-StubLine 'Connect-Dw'; [pscustomobject]@{ BaseUrl = 'https://stub' } }
function Assert-DwConnection { Write-StubLine 'Assert-DwConnection'; $true }
function Remove-DwDisplayOnlyMember { param([Parameter(Mandatory = $true)]$Model) $Model }
function Get-StubSection([string]$Name) {
    if ($script:StubConfig.PSObject.Properties[$Name]) { return $script:StubConfig.$Name }
    $null
}
function Invoke-DwMcp {
    param([Parameter(Mandatory = $true)][string]$Tool, [hashtable]$Arguments = @{}, [switch]$Raw, [int]$TimeoutSec = 120)
    Write-StubLine "Invoke-DwMcp $Tool"
    Write-StubLine ("  args " + ($Arguments | ConvertTo-Json -Depth 20 -Compress))
    $mcp = Get-StubSection 'mcp'
    if ($mcp -and $mcp.PSObject.Properties[$Tool]) { return $mcp.$Tool }
    [pscustomobject]@{ status = 'ok' }
}
function Invoke-DwApi {
    param([Parameter(Mandatory = $true)][string]$Command, $Body, [string]$Method, [int]$TimeoutSec = 120)
    Write-StubLine "Invoke-DwApi $Command"
    if ($null -ne $Body) { Write-StubLine ("  body " + ($Body | ConvertTo-Json -Depth 20 -Compress)) }
    $api = Get-StubSection 'api'
    if ($api) {
        foreach ($p in $api.PSObject.Properties) {
            if ($Command -like "$($p.Name)*") {
                if ($p.Value -is [string] -and $p.Value -eq 'throw') { throw "stub: $($p.Name) unavailable" }
                return $p.Value
            }
        }
    }
    [pscustomobject]@{ status = 'ok' }
}
function Get-DwSqlScalar {
    param([Parameter(Mandatory = $true)][string]$Sql, [string]$ConnectionString)
    Write-StubLine ("Get-DwSqlScalar " + ($Sql -replace '\s+', ' '))
    foreach ($rule in @(Get-StubSection 'sqlScalar')) {
        if ($rule -and $Sql -like "*$($rule.match)*") { return $rule.value }
    }
    0
}
function Clear-DwServiceCache { param([string[]]$CacheTypeName, [switch]$All) foreach ($n in $CacheTypeName) { Write-StubLine "Clear-DwServiceCache $n" } }
Export-ModuleMember -Function Connect-Dw, Assert-DwConnection, Invoke-DwMcp, Invoke-DwApi, Get-DwSqlScalar, Clear-DwServiceCache, Remove-DwDisplayOnlyMember
'@
    Set-Content -LiteralPath (Join-Path $Destination 'stub-log-path.txt') -Value $LogPath -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $Destination 'Dw.Api.psm1') -Value $module -Encoding utf8NoBOM
    $copied
}

function New-StubbedMcpScript {
    # Thin wrapper for the assortment suite: the build-queue drain, the item
    # count and the shop-relation count are the three values it varies.
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [string[]]$PendingIds = @(),
        [int]$ItemCount = 0,
        [int]$ShopRelationCount = 0
    )
    New-StubbedApiScript -ScriptPath $ScriptPath -Destination $Destination -LogPath $LogPath -Config @{
        mcp       = @{
            get_assortments_for_build = @{ assortments = @($PendingIds | ForEach-Object { @{ assortmentId = $_ } }) }
            get_assortment            = @{ assortment = @{ assortmentId = 'ASRT1'; active = $false } }
        }
        sqlScalar = @(
            @{ match = 'EcomAssortmentItems'; value = $ItemCount },
            @{ match = 'EcomAssortmentShopRelations'; value = $ShopRelationCount }
        )
    }
}
