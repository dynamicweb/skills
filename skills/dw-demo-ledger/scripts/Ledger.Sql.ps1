<#
.SYNOPSIS
READ-ONLY. Local SQL SELECT observations with integrated authentication.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/contract.md. Optional fallback for observations not supplied by higher surfaces. No cache flush is owed by reads. Rejects remote servers and anything but one SELECT statement, and runs every read inside a transaction that is always rolled back. Native SqlDataReader avoids sqlcmd display truncation.
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
# Statement keywords that may not appear as executable tokens. T-SQL needs no separator between
# statements, so a keyword after a complete SELECT starts a second statement in the same batch.
function Get-LedgerSqlRefusedPattern {
    return '(?i)\b(insert|update|delete|merge|drop|alter|truncate|create|exec|execute|into|openrowset|opendatasource|openquery|openxml|xp_\w+|sp_\w+|grant|revoke|deny|backup|restore|dbcc|kill|shutdown|reconfigure|checkpoint|waitfor|receive|send|use|begin|commit|rollback|save|tran|transaction|set|declare|disable|enable|trigger|login|bulk|readtext|writetext|updatetext|print|raiserror|throw|goto|while|if|return|open|fetch|close|deallocate|cursor|setuser|revert|dump|load|go|next\s+value\s+for)\b'
}
function Get-LedgerSqlCode {
    # The executable tokens of a query: string literals become '' and delimited identifiers [i].
    # Quoted data such as N'/*' is not a comment, and a quote inside [a'b] or "a'b" opens no literal.
    param([string]$Query)
    $code=[Text.StringBuilder]::new();$i=0
    while($i -lt $Query.Length){
        $open=$Query[$i];$close=switch($open){"'" {"'"} '"' {'"'} '[' {']'} default {$null}}
        if($null -eq $close){$null=$code.Append($open);$i++;continue}
        $i++;$closed=$false
        while($i -lt $Query.Length){
            if($Query[$i] -ne $close){$i++;continue}
            if($i+1 -lt $Query.Length -and $Query[$i+1] -eq $close){$i+=2;continue}
            $closed=$true;$i++;break
        }
        if(-not $closed){throw 'Only a single local SELECT observation is allowed.'}
        $null=$code.Append($(if($open -eq "'"){"''"}else{'[i]'}))
    }
    return $code.ToString()
}
function Assert-LedgerSelect {
    param([string]$Query)
    $refusal='Only a single local SELECT observation is allowed.'
    $code=Get-LedgerSqlCode $Query
    if ($code -notmatch '^\s*SELECT\b' -or $code -match (Get-LedgerSqlRefusedPattern) -or $code -match ';|--|/\*') {throw $refusal}
    # One statement: outside parentheses a SELECT opens the query or follows a set operator.
    $top=[Text.StringBuilder]::new();$depth=0
    foreach($c in $code.ToCharArray()){
        if($c -eq '('){$depth++}
        elseif($c -eq ')'){$depth--;if($depth -lt 0){throw $refusal};if($depth -eq 0){$null=$top.Append('()')}}
        elseif($depth -eq 0){$null=$top.Append($c)}
    }
    if($depth -ne 0){throw $refusal}
    $selects=[regex]::Matches($top.ToString(),'(?i)\bselect\b').Count
    $allowed=[regex]::Matches($top.ToString(),'(?i)(?:^\s*|\b(?:union(?:\s+all)?|except|intersect)\s+)select\b').Count
    if($selects -ne $allowed){throw $refusal}
}
function New-LedgerSqlConnection {
    param([string]$Server,[string]$Database)
    $builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source']=$Server; $builder['Initial Catalog']=$Database; $builder['Integrated Security']=$true; $builder['Connect Timeout']=10
    return [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
}
function Invoke-Sqlcmd-Rows {
    param([string]$Server,[string]$Database,[string]$Query)
    Assert-LedgerLocalServer $Server
    Assert-LedgerSelect $Query
    $connection=New-LedgerSqlConnection $Server $Database
    try {
        $connection.Open()
        # Read-only is a property of the execution, not only of the text: nothing this read does is ever committed.
        $transaction=$connection.BeginTransaction()
        try {
            $command=$connection.CreateCommand(); $command.Transaction=$transaction; $command.CommandText=$Query; $command.CommandTimeout=30
            try {
                $reader=$command.ExecuteReader(); $rows=[Collections.Generic.List[string]]::new()
                try {while($reader.Read()) {if($reader.IsDBNull(0)){throw 'NULL observation is not an empty result.'}; $rows.Add([string]$reader.GetValue(0))}} finally {$reader.Dispose()}
            } finally {$command.Dispose()}
            return $rows.ToArray()
        } finally {
            # A transaction the server already ended cannot be rolled back twice; the read's own error stays the one reported.
            try {$transaction.Rollback()} catch {Write-Verbose 'Transaction was already ended by the server.'}
            $transaction.Dispose()
        }
    } finally {$connection.Dispose()}
}
function Invoke-Sqlcmd-Scalar {
    param([string]$Server,[string]$Database,[string]$Query)
    $rows=@(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query $Query)
    if ($rows.Count -ne 1 -or $rows[0] -notmatch '^-?\d+$') {throw 'Expected exactly one integer SQL observation.'}
    return [long]$rows[0]
}
