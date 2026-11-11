<#
.SYNOPSIS
READ-ONLY. Discover authenticated read surfaces and normalise MCP observations.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. Imports the shared API transport. Credentials remain in process memory; exception bodies are never emitted. A public descriptor does not prove authentication.
.EXAMPLE
. ./Ledger.Transport.ps1
#>
#Requires -Version 7.0
function Get-LedgerCapabilities {
    param([string]$BaseUrl,[string]$ApiToken,[string]$McpToken,[string]$SqlServer,[string]$FilesPath,[switch]$AllowSelfSignedCertificate)
    $cap=@{schema=1;dwVersion=$null;discoveredAt=[DateTimeOffset]::UtcNow.ToString('o');mcp=@{available=$false;tools=@()};adminApi=@{available=$false;authenticated=$false;queries=@()};dwapi=@{available=$false};file=@{available=$false;local=$false};sql=@{available=$false;localOnly=$true};facts=@{};errors=@()}
    if ($SqlServer) {Assert-LedgerLocalServer $SqlServer; $cap.sql.available=$true}
    if ($FilesPath) { $cap.file.available=Test-Path -LiteralPath $FilesPath -PathType Container; $cap.file.local=$cap.file.available }
    if (-not $BaseUrl) {return $cap}
    Import-Module (Join-Path $PSScriptRoot '../../dw-data-access/scripts/Dw.Api.psm1') -Force -ErrorAction Stop
    Connect-Dw -BaseUrl $BaseUrl -ApiToken $ApiToken -McpToken $McpToken -AllowSelfSignedCertificate:$AllowSelfSignedCertificate | Out-Null
    Assert-DwConnection | Out-Null
    $skip=$AllowSelfSignedCertificate -or $BaseUrl -match '^https?://(localhost|127\.0\.0\.1)([:/]|$)'
    try {
        $spec=Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+'/admin/api/api.json') -TimeoutSec 20 -SkipCertificateCheck:$skip
        $cap.adminApi.available=$true
        if($spec.info.version) {$cap.dwVersion=[string]$spec.info.version}
        $cap.adminApi.queries=@($spec.paths.PSObject.Properties | Where-Object {$_.Value.get} | ForEach-Object {$_.Name.TrimStart('/')})
        if ($ApiToken -and 'McpConfigurationAll' -in $cap.adminApi.queries) {
            try {$null=Invoke-DwApi 'McpConfigurationAll';$cap.adminApi.authenticated=$true} catch {$cap.errors+='Admin authenticated read failed.'}
        }
    } catch {$cap.errors+='Admin descriptor could not be read.'}
    if($McpToken){try{$tools=Get-DwMcpTools;$cap.mcp.tools=@($tools.name);$cap.mcp.available=$true}catch{$cap.errors+='MCP discovery failed.'}}
    # Delivery-route reachability is not recorded as usable until a claim-specific read proves it.
    return $cap
}
function Read-LedgerMcp {
    param([string]$Operation,[hashtable]$Arguments=@{})
    $key=$Operation+($Arguments|ConvertTo-Json -Compress -Depth 10)
    if($script:LedgerMcpCache.ContainsKey($key)){return $script:LedgerMcpCache[$key]}
    $raw=Invoke-DwMcp -Tool $Operation -Arguments $Arguments -Raw -TimeoutSec 30
    if($raw.isError){
        if(($raw.content.text -join ' ') -match '(?i)not allowed|access denied|unauthorized|forbidden'){throw [UnauthorizedAccessException]::new('MCP read is not authorised for the requested scope.')}
        throw 'MCP returned an error result.'
    }
    $data=if($raw.structuredContent){$raw.structuredContent|ConvertTo-Json -Depth 80|ConvertFrom-Json -AsHashtable}else{($raw.content.text -join "`n")|ConvertFrom-Json -AsHashtable}
    if(-not $data.ContainsKey('data')){throw 'MCP observation has no data envelope.'}
    $null=ConvertTo-LedgerRows $data
    $script:LedgerMcpCache[$key]=$data
    return $data
}
function Assert-LedgerFields {
    param([object[]]$Rows,[string[]]$Fields)
    foreach($row in $Rows){foreach($field in $Fields){if(-not $row.ContainsKey($field)){throw [InvalidOperationException]::new('Required observation field is missing.')}}}
}
function Get-LedgerMcpObservation {
    param($Binding,$Check,$Build)
    $args=@{}; if($Binding.arguments){$args=$Binding.arguments.Clone()}
    if($Binding.handler -eq 'mcp-files-count'){$args=@{path=$Binding.arguments.path}}
    $args=Expand-LedgerArguments $args $Build
    $result=Read-LedgerMcp -Operation $Binding.operation -Arguments $args
    $rows=@($result.data);$value=0;$offenders=@();$complete=$true
    switch($Binding.handler){
        'mcp-files-count' {
            Assert-LedgerFields $rows @('path','name','isDirectory')
            $files=@($rows|Where-Object {-not $_.isDirectory})
            if($Binding.arguments.includeSubfolders){foreach($dir in @($rows|Where-Object {$_.isDirectory})){
                $child=Read-LedgerMcp -Operation 'list_files' -Arguments @{path=$dir.path}
                Assert-LedgerFields @($child.data) @('name','isDirectory')
                $files+=@($child.data|Where-Object {-not $_.isDirectory})
            }}
            $value=@($files|Where-Object {$_.name -like $Binding.arguments.filter}).Count
        }
        'mcp-count' {return Measure-LedgerRows $rows $Binding.projection}
        'mcp-workspace-count' {Assert-LedgerFields $rows @('levels');$value=@($rows|Where-Object {@($_.levels).Count -gt 0}).Count}
        'mcp-workspace-empty' {Assert-LedgerFields $rows @('levels','id');$offenders=@($rows|Where-Object {@($_.levels).Count -eq 0}|ForEach-Object {$_.id})}
        'mcp-workspace-completeness' {Assert-LedgerFields $rows @('levels');$levels=@($rows|ForEach-Object {$_.levels});Assert-LedgerFields $levels @('useCompleteness');$value=@($levels|Where-Object {$_.useCompleteness -eq $true}).Count}
        'mcp-workflow-states' {Assert-LedgerFields $rows @('states');foreach($row in $rows){$value=[Math]::Max($value,@($row.states).Count)}}
        'mcp-workflow-transitions' {
            Assert-LedgerFields $rows @('states');$states=@($rows|ForEach-Object {$_.states});Assert-LedgerFields $states @('id','nextStateIds')
            $ids=@($states|ForEach-Object {$_.id});foreach($state in $states){$value+=@($state.nextStateIds|Where-Object {$_ -in $ids}).Count}
        }
        'mcp-completion-rules' {Assert-LedgerFields $rows @('fieldSystemNames');$value=@($rows|Where-Object {@($_.fieldSystemNames).Count -ge 3}).Count}
        'mcp-dashboard-count' {Assert-LedgerFields $rows @('dashboardType','widgetCount');$value=@($rows|Where-Object {$_.dashboardType -eq 'Products' -and $_.widgetCount -ge 4}).Count}
        'mcp-field-types' {
            Assert-LedgerFields $rows @('categoryId','typeId');$types=@($rows|Where-Object {$_.categoryId -ne 'reference_category'}|ForEach-Object {if($_.typeId -in @(1,10,11,12,13)){1}else{$_.typeId}}|Sort-Object -Unique);$value=$types.Count
        }
        'mcp-field-text-share' {
            Assert-LedgerFields $rows @('categoryId','typeId');$fields=@($rows|Where-Object {$_.categoryId -ne 'reference_category'})
            $value=if($fields.Count){[Math]::Floor(100*@($fields|Where-Object {$_.typeId -in @(1,10,11,12,13)}).Count/$fields.Count)}else{100}
        }
        'mcp-multiselect' {
            # The current DTO omits presentation. Do not guess from option counts.
            if(@($rows|Where-Object {-not $_.ContainsKey('presentation')}).Count){$complete=$false;break}
            $value=@($rows|Where-Object {$_.typeId -eq 15 -and $_.presentation -in @(3,4) -and $_.categoryId -ne 'reference_category'}).Count
        }
        default {throw 'No registered MCP observation handler.'}
    }
    return @{value=$value;offenders=$offenders;scanned=$rows.Count;complete=$complete}
}
