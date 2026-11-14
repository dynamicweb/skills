<#
.SYNOPSIS
READ-ONLY. Discover authenticated read surfaces and normalise MCP observations.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. Imports the shared API transport. Credentials remain in process memory; exception bodies are never emitted. A public descriptor does not prove authentication.
.EXAMPLE
. ./Ledger.Transport.ps1
#>
#Requires -Version 7.0
function Read-LedgerDescriptor {
    # The public descriptor identifies the release. One failed read is retried, so a hiccup is not reported as another release.
    param([string]$BaseUrl,[switch]$AllowSelfSignedCertificate,[int]$Attempts=3,[int]$DelayMs=1000)
    $skip=$AllowSelfSignedCertificate -or $BaseUrl -match '^https?://(localhost|127\.0\.0\.1)([:/]|$)'
    for($attempt=1;;$attempt++){
        try{return Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/')+'/admin/api/api.json') -TimeoutSec 20 -SkipCertificateCheck:$skip}
        catch{if($attempt -ge $Attempts){throw};Start-Sleep -Milliseconds ($DelayMs*$attempt)}
    }
}
function Get-LedgerObservedVersion {
    param([string]$BaseUrl,[switch]$AllowSelfSignedCertificate)
    if(-not $BaseUrl){return $null}
    try {
        $spec=Read-LedgerDescriptor -BaseUrl $BaseUrl -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
        return [string]$spec.info.version
    }catch{return $null}
}
function Test-LedgerStableVersion {
    param([string]$Before,[string]$After)
    return -not [string]::IsNullOrWhiteSpace($Before) -and -not [string]::IsNullOrWhiteSpace($After) -and $Before -ceq $After
}
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
    $script:LedgerTarget=@{baseUrl=$BaseUrl.TrimEnd('/');insecure=[bool]$skip}
    try {
        $spec=Read-LedgerDescriptor -BaseUrl $BaseUrl -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
        $cap.adminApi.available=$true
        # The host answers. A delivery read still proves its own claim: the route, the projection and completeness.
        $cap.dwapi.available=$true
        if($spec.info.version) {$cap.dwVersion=[string]$spec.info.version}
        $cap.adminApi.queries=@($spec.paths.PSObject.Properties | Where-Object {$_.Value.get} | ForEach-Object {$_.Name.TrimStart('/')})
        if ($ApiToken -and 'McpConfigurationAll' -in $cap.adminApi.queries) {
            try {$null=Invoke-DwApi 'McpConfigurationAll';$cap.adminApi.authenticated=$true} catch {$cap.errors+='Admin authenticated read failed.'}
        }
    } catch {$cap.errors+='Admin descriptor could not be read after 3 attempts.'}
    if($McpToken){try{$tools=Get-DwMcpTools;$cap.mcp.tools=@($tools.name);$cap.mcp.available=$true}catch{$cap.errors+='MCP discovery failed.'}}
    if($cap.adminApi.authenticated -and 'FeaturesAll' -in $cap.adminApi.queries){
        try {$cap.facts=Get-LedgerFeatureFacts (Invoke-DwApi 'FeaturesAll')} catch {$cap.errors+='Complete feature flag observation unavailable.'}
    }
    return $cap
}
function Get-LedgerFeatureFacts {
    param($Response)
    $data=$Response|ConvertTo-Json -Depth 30|ConvertFrom-Json -AsHashtable
    $model=Get-LedgerField $data 'model'
    if(-not $model.ContainsKey('totalCount') -or -not $model.ContainsKey('totalPages')){throw [InvalidOperationException]::new('Feature enumeration has no completeness evidence.')}
    $rows=ConvertTo-LedgerRows $model 'data';$facts=@{}
    foreach($row in $rows){
        Assert-LedgerFields @($row) @('featureTypeName','active')
        if([string]::IsNullOrWhiteSpace($row.featureTypeName) -or $row.active -isnot [bool] -or $facts.ContainsKey($row.featureTypeName)){throw [InvalidOperationException]::new('Ambiguous feature flag observation.')}
        $facts[$row.featureTypeName]=$row.active
    }
    return $facts
}
function Read-LedgerMcp {
    param([string]$Operation,[hashtable]$Arguments=@{})
    # The runner is read-only: only a tool on the read allowlist is ever called, whatever a binding names.
    if($Operation -cnotin @((Read-LedgerJson (Join-Path $PSScriptRoot '../assets/handlers.json')).mcpReadTools)){throw 'MCP tool is not an allowlisted read tool.'}
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
function ConvertFrom-LedgerPersonaCredential {
    # DW_PERSONA_CREDENTIALS: a JSON array of {userName, password, userId?}. Returns the list, or
    # throws a fault that names the shape only: the value is a secret and is never quoted.
    param([string]$Text)
    if([string]::IsNullOrWhiteSpace($Text)){return ,@()}
    try{$parsed=ConvertFrom-Json -InputObject $Text -AsHashtable -NoEnumerate}catch{throw [InvalidOperationException]::new('Runner input: persona credentials (DW_PERSONA_CREDENTIALS) are not a JSON array of {userName, password}.')}
    if($parsed -isnot [array] -or @($parsed).Count -eq 0){throw [InvalidOperationException]::new('Runner input: persona credentials (DW_PERSONA_CREDENTIALS) are not a JSON array of {userName, password}.')}
    $list=foreach($entry in $parsed){
        if($entry -isnot [Collections.IDictionary] -or $entry.userName -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.userName) -or
           $entry.password -isnot [string] -or $entry.password -eq '' -or ($entry.Contains('userId') -and $entry.userId -isnot [long] -and $entry.userId -isnot [int]) -or
           @($entry.Keys|Where-Object {$_ -cnotin @('userName','password','userId')}).Count){
            throw [InvalidOperationException]::new('Runner input: persona credentials (DW_PERSONA_CREDENTIALS) are not a JSON array of {userName, password}.')
        }
        @{userName=$entry.userName;password=$entry.password;userId=$(if($entry.Contains('userId')){[long]$entry.userId}else{$null})}
    }
    return ,@($list)
}
function Get-LedgerPersonaSignInObservation {
    # Each supplied persona signs in (POST users/authenticate) and is then served one read as that user
    # (GET <readAs> with the issued token), which must name the same user. 1 when every persona does, else 0.
    # The password and the token stay in this function: no row, reason or offender carries either, and no
    # response body is kept.
    param($Binding)
    $registry=Read-LedgerJson (Join-Path $PSScriptRoot '../assets/handlers.json')
    if($Binding.operation -cnotin @($registry.dwapiSignInRoutes)){throw 'Sign-in route is not allowlisted for the sign-in handler.'}
    $readAs=if($Binding.arguments){$Binding.arguments.readAs}else{$null}
    if($readAs -isnot [string] -or $readAs -cnotin @($registry.dwapiSignedInReadRoutes)){throw 'The read made as the persona is not an allowlisted signed-in read route.'}
    if(-not $script:LedgerTarget -or -not $script:LedgerTarget.baseUrl){throw [InvalidOperationException]::new('Target URL is unavailable.')}
    $personas=ConvertFrom-LedgerPersonaCredential $env:DW_PERSONA_CREDENTIALS
    if($personas.Count -eq 0){throw [InvalidOperationException]::new('Runner input: persona credentials are not supplied (DW_PERSONA_CREDENTIALS), so no sign-in can be observed.')}
    $base=$script:LedgerTarget.baseUrl;$insecure=$script:LedgerTarget.insecure
    $offenders=[Collections.Generic.List[object]]::new()
    foreach($persona in $personas){
        $body=@{username=$persona.userName;password=$persona.password}|ConvertTo-Json -Compress
        $sign=Invoke-WebRequest -Uri ($base+'/dwapi/'+$Binding.operation) -Method Post -Body $body -ContentType 'application/json' -Headers @{Accept='application/json'} -TimeoutSec 30 -SkipHttpErrorCheck -SkipCertificateCheck:$insecure
        $status=[int]$sign.StatusCode
        if($status -ge 500){throw 'Sign-in request failed on the server.'}
        $token=$null
        if($status -eq 200){
            try{$answer=ConvertFrom-Json -InputObject ([string]$sign.Content) -AsHashtable}catch{$answer=$null}
            if($answer -is [Collections.IDictionary] -and $answer.token -is [string] -and $answer.token.Trim()){$token=$answer.token}
        }
        if(-not $token){$offenders.Add([ordered]@{userName=$persona.userName;step='sign-in';status=$status;reason='No token was issued.'});continue}
        $read=Invoke-WebRequest -Uri ($base+'/dwapi/'+$readAs) -Method Get -Headers @{Accept='application/json';Authorization='Bearer '+$token} -TimeoutSec 30 -SkipHttpErrorCheck -SkipCertificateCheck:$insecure
        $token=$null
        $status=[int]$read.StatusCode
        if($status -ge 500){throw 'Signed-in read failed on the server.'}
        $user=$null
        if($status -eq 200){try{$user=ConvertFrom-Json -InputObject ([string]$read.Content) -AsHashtable}catch{$user=$null}}
        if($user -isnot [Collections.IDictionary]){$offenders.Add([ordered]@{userName=$persona.userName;step='read-as-user';status=$status;reason="GET $readAs as the persona returned no user."});continue}
        $sameName=$user.userName -is [string] -and [string]::Equals($user.userName,$persona.userName,[StringComparison]::OrdinalIgnoreCase)
        $sameId=$null -eq $persona.userId -or ($null -ne $user.id -and "$($user.id)" -eq "$($persona.userId)")
        if(-not($sameName -and $sameId)){$offenders.Add([ordered]@{userName=$persona.userName;step='read-as-user';status=$status;reason="GET $readAs as the persona was served another user."})}
    }
    return @{value=[int]($offenders.Count -eq 0);scanned=$personas.Count;offenders=$offenders.ToArray();complete=$true}
}
function Get-LedgerDwapiObservation {
    # One anonymous GET on an allowlisted delivery route. No credential is sent and no other method exists here.
    param($Binding,$Build)
    if($Binding.handler -eq 'dwapi-persona-sign-in'){return Get-LedgerPersonaSignInObservation $Binding}
    if($Binding.handler -ne 'dwapi-count'){throw 'No registered delivery observation handler.'}
    if($Binding.operation -cnotin @((Read-LedgerJson (Join-Path $PSScriptRoot '../assets/handlers.json')).dwapiReadRoutes)){throw 'Delivery route is not an allowlisted read route.'}
    if(-not $script:LedgerTarget -or -not $script:LedgerTarget.baseUrl){throw [InvalidOperationException]::new('Target URL is unavailable.')}
    if(-not $Binding.projection.rowsPath){throw [InvalidOperationException]::new('Delivery read needs an explicit measured row projection.')}
    $route=[string](Expand-LedgerArguments $Binding.operation $Build)
    if($route -notmatch '^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$'){throw 'Delivery route input is not a plain id.'}
    $query=if($Binding.arguments){Expand-LedgerArguments $Binding.arguments $Build}else{@{}}
    $pairs=@(foreach($key in @($query.Keys|Sort-Object)){[Uri]::EscapeDataString($key)+'='+[Uri]::EscapeDataString([string]$query[$key])})
    $uri=$script:LedgerTarget.baseUrl+'/dwapi/'+$route;if($pairs.Count){$uri+='?'+($pairs -join '&')}
    $response=Invoke-WebRequest -Uri $uri -Method Get -Headers @{Accept='application/json'} -TimeoutSec 30 -SkipHttpErrorCheck -SkipCertificateCheck:$script:LedgerTarget.insecure
    $status=[int]$response.StatusCode
    if($status -in @(401,403)){throw [UnauthorizedAccessException]::new('Delivery read is not authorised without a credential.')}
    if($status -eq 404){throw [InvalidOperationException]::new('Delivery route is not served by this target.')}
    if($status -ne 200){throw 'Delivery read failed.'}
    $text=if($response.Content -is [byte[]]){[Text.Encoding]::UTF8.GetString($response.Content)}else{[string]$response.Content}
    $data=ConvertFrom-Json -InputObject $text -AsHashtable -NoEnumerate
    $rows=ConvertTo-LedgerRows $data $Binding.projection.rowsPath
    return Measure-LedgerRows $rows $Binding.projection
}
