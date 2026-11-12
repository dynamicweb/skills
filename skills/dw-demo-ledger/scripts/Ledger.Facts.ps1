<#
.SYNOPSIS
READ-ONLY. Discover the app and settings facts the requested functions' requirements name.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. An installed app is a folder
<id>.<version> under Files/System/AddIns/Installed, read from the local Files root or, without
one, through the MCP file listing. A settings path is read from the GlobalSettings*.config
layers at the local Files root. Absence is never a fact: an app compiled into the host and a
setting left at its default stay unknown. Only the ids a requirement names are recorded.
.EXAMPLE
. ./Ledger.Facts.ps1
Add-LedgerRequirementFacts -Capabilities $cap -Requirements $requirements -FilesPath $files
#>
#Requires -Version 7.0
function Get-LedgerInstalledApps {
    # Folder names to id -> version. Two versions of one id are not one fact, so that id maps to $null.
    param([string[]]$Names)
    $apps=@{}
    foreach($name in $Names){
        if($name -notmatch '^(?<id>[A-Za-z][A-Za-z0-9_.-]*?)\.(?<version>\d+\.\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.-]+)?)$'){continue}
        $id=$Matches.id
        $apps[$id]=if($apps.ContainsKey($id)){$null}else{$Matches.version}
    }
    return $apps
}
function Get-LedgerSettingFact {
    # $true or $false when the layers that state the key agree on an explicit boolean; otherwise $null.
    param([string]$FilesPath,[string]$Key)
    if($Key -notmatch '^/Globalsettings/(?:[A-Za-z][A-Za-z0-9]*/)*[A-Za-z][A-Za-z0-9]*$'){return $null}
    $values=[Collections.Generic.List[bool]]::new()
    foreach($file in Get-ChildItem -LiteralPath $FilesPath -Filter 'GlobalSettings*.config' -File -Force){
        try{$nodes=(Read-LedgerXml $file.FullName).SelectNodes($Key)}catch{return $null}
        if($nodes.Count -eq 0){continue}
        $parsed=$false
        if($nodes.Count -ne 1 -or -not [bool]::TryParse($nodes[0].InnerText.Trim(),[ref]$parsed)){return $null}
        $values.Add($parsed)
    }
    if($values.Count -eq 0 -or @($values|Select-Object -Unique).Count -ne 1){return $null}
    return $values[0]
}
function Add-LedgerRequirementFacts {
    # Adds app:<id> (the installed version) and setting:<path> (a boolean) to the discovered facts.
    param($Capabilities,[object[]]$Requirements,[string]$FilesPath)
    $appIds=@($Requirements|Where-Object {$_.kind -eq 'app'}|ForEach-Object {[string]$_.id}|Select-Object -Unique)
    $settings=@($Requirements|Where-Object {$_.kind -eq 'flag' -and "$($_.id)".StartsWith('/Globalsettings/')}|ForEach-Object {[string]$_.id}|Select-Object -Unique)
    if($appIds.Count){
        $names=$null
        $folder=if($Capabilities.file.local){Join-Path $FilesPath 'System/AddIns/Installed'}else{$null}
        if($folder -and (Test-Path -LiteralPath $folder -PathType Container)){
            $names=@(Get-ChildItem -LiteralPath $folder -Directory -Force|ForEach-Object Name)
        } elseif($Capabilities.mcp.available -and 'list_files' -in $Capabilities.mcp.tools){
            try{
                $listing=Read-LedgerMcp -Operation 'list_files' -Arguments @{path='/Files/System/AddIns/Installed'}
                Assert-LedgerFields @($listing.data) @('name','isDirectory')
                $names=@($listing.data|Where-Object {$_.isDirectory}|ForEach-Object {[string]$_.name})
            }catch{$Capabilities.errors+='Installed app listing is unavailable over MCP.'}
        }
        if($null -ne $names){
            $apps=Get-LedgerInstalledApps $names
            foreach($id in $appIds){if($apps[$id]){$Capabilities.facts['app:'+$id]=$apps[$id]}}
        }
    }
    if($Capabilities.file.local){foreach($key in $settings){
        $value=Get-LedgerSettingFact $FilesPath $key
        if($null -ne $value){$Capabilities.facts['setting:'+$key]=$value}
    }}
}
