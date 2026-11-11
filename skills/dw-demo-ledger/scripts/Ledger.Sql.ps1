<#
.SYNOPSIS
READ-ONLY. Local SQL SELECT observations with integrated authentication.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. Optional fallback for observations not supplied by higher surfaces. No cache flush is owed by reads. Rejects remote servers and non-SELECT statements. Native SqlDataReader avoids sqlcmd display truncation.
.EXAMPLE
. ./Ledger.Sql.ps1
#>
#Requires -Version 7.0
function Assert-LedgerLocalServer {
    param([string]$Server)
    $hostPart = ($Server -split '\\')[0]
    if ($hostPart -notin @('.','(local)','localhost','127.0.0.1',$env:COMPUTERNAME)) { throw 'SQL binding requires an explicit local server.' }
    if ($Server -match '[;,\s]') {throw 'Invalid local SQL server identifier.'}
}
function Assert-LedgerSelect {
    param([string]$Query)
    if ($Query -notmatch '^\s*SELECT\b' -or $Query -match '(?i)\b(insert|update|delete|merge|drop|alter|truncate|exec|execute|into|openrowset|opendatasource|openquery|xp_\w+)\b|;|--|/\*') {throw 'Only a single local SELECT observation is allowed.'}
}
function Invoke-Sqlcmd-Rows {
    param([string]$Server,[string]$Database,[string]$Query)
    Assert-LedgerLocalServer $Server
    Assert-LedgerSelect $Query
    $builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source']=$Server; $builder['Initial Catalog']=$Database; $builder['Integrated Security']=$true; $builder['Connect Timeout']=10
    $connection=[System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try {
        $connection.Open(); $command=$connection.CreateCommand(); $command.CommandText=$Query; $command.CommandTimeout=30
        $reader=$command.ExecuteReader(); $rows=[Collections.Generic.List[string]]::new()
        try {while($reader.Read()) {if($reader.IsDBNull(0)){throw 'NULL observation is not an empty result.'}; $rows.Add([string]$reader.GetValue(0))}} finally {$reader.Dispose();$command.Dispose()}
        return $rows.ToArray()
    } finally {$connection.Dispose()}
}
function Invoke-Sqlcmd-Scalar {
    param([string]$Server,[string]$Database,[string]$Query)
    $rows=@(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query $Query)
    if ($rows.Count -ne 1 -or $rows[0] -notmatch '^-?\d+$') {throw 'Expected exactly one integer SQL observation.'}
    return [long]$rows[0]
}
