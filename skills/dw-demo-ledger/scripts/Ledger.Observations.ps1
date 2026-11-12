<#
.SYNOPSIS
READ-ONLY. Typed tokens, complete collection projections and local XML observations.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. No evaluated expressions,
external XML entities or paths outside the supplied Files root. Missing scope is unverified.
.EXAMPLE
. ./Ledger.Observations.ps1
#>
#Requires -Version 7.0
function Expand-LedgerArguments {
    param($Value,$Build)
    if($Value -is [Collections.IDictionary]) {
        $copy=@{};foreach($key in $Value.Keys){$copy[$key]=Expand-LedgerArguments $Value[$key] $Build};return $copy
    }
    if($Value -is [array]) {return ,@(foreach($item in $Value){Expand-LedgerArguments $item $Build})}
    if($Value -isnot [string]) {return $Value}
    $tokens=@{lang=$Build.defaultLanguage;pimShop=$Build.pimShop;areaId=$Build.areaId}
    foreach($match in [regex]::Matches($Value,'\{([^{}]+)\}')) {
        $key=$match.Groups[1].Value
        if(-not $tokens.ContainsKey($key) -or $null -eq $tokens[$key] -or "$($tokens[$key])" -eq '') {
            throw [InvalidOperationException]::new('Required argument token is not declared.')
        }
        if($Value -eq $match.Value){return $tokens[$key]}
        $Value=$Value.Replace($match.Value,[string]$tokens[$key])
    }
    return $Value
}
function Get-LedgerField {
    param($Row,[string]$Path)
    $current=$Row
    foreach($key in $Path.Split('.')) {
        if($current -isnot [Collections.IDictionary] -or -not $current.Contains($key)) {
            throw [InvalidOperationException]::new('Required observation field is missing.')
        }
        $current=$current[$key]
    }
    return ,$current
}
function Measure-LedgerRows {
    param([object[]]$Rows,$Projection)
    $selected=$Rows
    if($Projection -and $Projection.filter){
        $filter=$Projection.filter
        $selected=@(foreach($item in $Rows){
            $value=Get-LedgerField $item $filter.field
            $expected=$filter.value;$matches=$false
            switch($filter.op){
                'equals' {$matches=($value|ConvertTo-Json -Compress -Depth 20) -ceq ($expected|ConvertTo-Json -Compress -Depth 20)}
                'contains' {
                    if($value -isnot [string] -or $expected -isnot [string]){throw [InvalidOperationException]::new('Contains requires a text field and value.')}
                    $matches=$value.Contains($expected,[StringComparison]::Ordinal)
                }
                default {throw 'Unknown field filter comparator.'}
            }
            if($matches){$item}
        })
    }
    return @{value=@($selected).Count;scanned=$Rows.Count;offenders=@();complete=$true}
}
function ConvertTo-LedgerRows {
    param($Data,[string]$RowsPath='data')
    $rows=$Data
    if($RowsPath -ne '$'){$rows=Get-LedgerField $Data $RowsPath}
    if($null -eq $rows -or $rows -isnot [array]){throw [InvalidOperationException]::new('Expected an explicit array projection.')}
    if($Data -is [Collections.IDictionary]){
        foreach($key in @('count','total','totalCount')){
            if($Data.Contains($key) -and $Data[$key] -ne $rows.Count){throw [InvalidOperationException]::new('Collection enumeration is incomplete.')}
        }
        if($Data.totalPages -gt 1 -or $Data.hasMore -or $Data.hasNextPage -or $Data.nextCursor -or $Data.nextLink){throw [InvalidOperationException]::new('Paged collection is not complete.')}
    }
    return ,$rows
}
function Get-LedgerLocalFiles {
    param($Binding,[string]$FilesPath)
    if(-not $FilesPath -or -not(Test-Path -LiteralPath $FilesPath -PathType Container)){throw [InvalidOperationException]::new('Files root is unavailable.')}
    if((Get-Item -LiteralPath $FilesPath).Attributes -band [IO.FileAttributes]::ReparsePoint){throw [InvalidOperationException]::new('Linked Files root cannot establish local scope.')}
    if($Binding.path){
        $relative=$Binding.path.Replace('\','/')
        if($relative.StartsWith('/Files/')){$relative=$relative.Substring(7)}
        $null=Resolve-LedgerPath $FilesPath $relative
        if($relative -match '[:\[\]]|\*\*' -or $relative.Split('/') -contains '..'){throw 'Invalid file pattern.'}
        $parts=$relative.Split('/');$dirs=@((Resolve-Path -LiteralPath $FilesPath).Path)
        for($i=0;$i -lt $parts.Count;$i++){
            $next=@(foreach($dir in $dirs){
                Get-ChildItem -LiteralPath $dir -ErrorAction Stop | Where-Object {
                    $_.Name -like $parts[$i] -and
                    ($_.PSIsContainer -eq ($i -lt $parts.Count-1))
                } | ForEach-Object {
                    if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw [InvalidOperationException]::new('Linked file scope is unavailable.')}
                    $_.FullName
                }
            })
            $dirs=$next
        }
        return ,$dirs
    }
    if(-not $Binding.arguments.folder -or -not $Binding.arguments.filter){throw 'File count needs path or folder/filter.'}
    $folder=Resolve-LedgerPath $FilesPath $Binding.arguments.folder
    if(-not(Test-Path -LiteralPath $folder -PathType Container)){throw [InvalidOperationException]::new('Required file folder is unavailable.')}
    # Reject links in every directory component, not only the leaf.
    $cursor=Get-Item -LiteralPath $folder
    while($cursor.FullName -ne [IO.Path]::GetFullPath($FilesPath).TrimEnd('/','\')){
        if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw [InvalidOperationException]::new('Linked folder cannot establish local scope.')}
        $cursor=$cursor.Parent
        if(-not $cursor){throw 'Folder is outside the Files root.'}
    }
    $dirs=@($folder)
    if($Binding.arguments.includeSubfolders){$dirs+=@(Get-ChildItem -LiteralPath $folder -Directory -ErrorAction Stop | ForEach-Object {
        if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw [InvalidOperationException]::new('Linked folder scope is unavailable.')};$_.FullName
    })}
    return ,@(foreach($dir in $dirs){Get-ChildItem -LiteralPath $dir -Filter $Binding.arguments.filter -File -ErrorAction Stop | ForEach-Object {
        if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw [InvalidOperationException]::new('Linked file scope is unavailable.')};$_.FullName
    }})
}
function Read-LedgerXml {
    param([string]$Path)
    $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create($Path,$settings)
    try{$doc=[Xml.XmlDocument]::new();$doc.XmlResolver=$null;$doc.Load($reader);return ,$doc}finally{$reader.Dispose()}
}
function Get-LedgerFileObservation {
    param($Binding,[string]$FilesPath)
    $files=Get-LedgerLocalFiles $Binding $FilesPath
    if($Binding.handler -eq 'files-count'){return @{value=$files.Count;scanned=$files.Count;offenders=@();complete=$true}}
    if($Binding.handler -eq 'settings-value'){
        if($files.Count -ne 1){throw [InvalidOperationException]::new('Exactly one settings file is required.')}
        $key=$Binding.arguments.key
        if($key -notmatch '^/Globalsettings/(?:[A-Za-z][A-Za-z0-9]*/)*[A-Za-z][A-Za-z0-9]*$'){throw 'A literal Globalsettings key is required.'}
        $nodes=(Read-LedgerXml $files[0]).SelectNodes($key)
        if($nodes.Count -eq 0){throw [InvalidOperationException]::new('Setting is absent; platform default is not assumed.')}
        if($nodes.Count -ne 1){throw 'Duplicate settings key.'}
        if(-not $Binding.arguments.ContainsKey('equals')){throw 'Setting comparison value is required.'}
        $expected=$Binding.arguments.equals;$value=$nodes[0].InnerText
        if($expected -is [bool]){
            $actual=$false;if(-not [bool]::TryParse($value.Trim(),[ref]$actual)){throw [InvalidOperationException]::new('Setting is not an explicit boolean.')}
            $matches=$actual -eq $expected
        }else{$matches=$value -ceq [string]$expected}
        return @{value=[int]$matches;scanned=1;offenders=@();complete=$true}
    }
    if($Binding.handler -eq 'xml-count'){
        if(-not $Binding.arguments.xpath){throw 'XML count requires an explicit reviewed XPath.'}
        $value=0;foreach($file in $files){$value+=(Read-LedgerXml $file).SelectNodes($Binding.arguments.xpath).Count}
        return @{value=$value;scanned=$files.Count;offenders=@();complete=$true}
    }
    throw 'No registered file observation handler.'
}
function Get-LedgerAdminObservation {
    param($Binding,$Build,$Capabilities)
    if(-not $Capabilities.adminApi.authenticated){throw [UnauthorizedAccessException]::new('Authenticated API identity is required.')}
    if($Binding.operation -notmatch '^[A-Za-z][A-Za-z0-9]*$' -or $Binding.operation -notin $Capabilities.adminApi.queries){throw 'Only a discovered named GET query may execute.'}
    if($Binding.handler -eq 'admin-feature-flag'){
        $id=$Binding.arguments.featureTypeName
        if(-not $Capabilities.facts.ContainsKey($id)){throw [InvalidOperationException]::new('Feature state is unknown.')}
        return @{value=[int]($Capabilities.facts[$id] -eq $true);scanned=1;offenders=@();complete=$true}
    }
    $args=Expand-LedgerArguments $Binding.arguments $Build
    $pairs=@(foreach($key in $args.Keys){[Uri]::EscapeDataString($key)+'='+[Uri]::EscapeDataString([string]$args[$key])})
    $command=$Binding.operation;if($pairs.Count){$command+='?'+($pairs -join '&')}
    $data=Invoke-DwApi -Command $command -Method Get -TimeoutSec 30 -RetryCount 0
    $data=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $data -Depth 80) -AsHashtable -NoEnumerate
    if(-not $Binding.projection.rowsPath){throw [InvalidOperationException]::new('Admin query needs an explicit measured row projection.')}
    $rows=ConvertTo-LedgerRows $data $Binding.projection.rowsPath
    return Measure-LedgerRows $rows $Binding.projection
}
