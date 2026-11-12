<#
.SYNOPSIS
READ-ONLY. Read a complete, version-scoped CPQ snapshot through local SQL.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/cpq-observations.md.
Requires Ledger.Sql.ps1. Fixed SELECT statements, typed parameters, integrated authentication,
and a serializable read transaction prevent mixed-version observations. No cache flush is owed.
.PARAMETER Server
Explicit local SQL server. Remote targets are refused.
.PARAMETER Database
Explicit target database. No connection string is accepted or persisted.
.PARAMETER ModelId
The declared model identity, checked against the version's owner.
.PARAMETER VersionId
The concrete model-version identity. Names and active flags are not substitutes.
.EXAMPLE
Get-CpqSqlSnapshot -Server $server -Database $database -ModelId 100000 -VersionId 100001
#>
#Requires -Version 7.0
function Invoke-CpqSelect {
    param($Connection, $Transaction, [string]$Query, [hashtable]$Parameters=@{})
    Assert-LedgerSelect $Query
    $command=$Connection.CreateCommand();$command.Transaction=$Transaction
    $command.CommandText=$Query;$command.CommandTimeout=30
    foreach($key in $Parameters.Keys){
        if($key -cnotmatch '^@[a-z]+$' -or $Parameters[$key] -isnot [int]){throw 'CPQ SELECT requires typed integer parameters.'}
        $null=$command.Parameters.Add($key,[Data.SqlDbType]::Int);$command.Parameters[$key].Value=$Parameters[$key]
    }
    $rows=[Collections.Generic.List[object]]::new()
    try {
        $reader=$command.ExecuteReader()
        try {
            while($reader.Read()){
                $row=@{}
                for($i=0;$i -lt $reader.FieldCount;$i++){$row[$reader.GetName($i)]=if($reader.IsDBNull($i)){$null}else{$reader.GetValue($i)}}
                $rows.Add($row)
            }
        } finally {$reader.Dispose()}
    } finally {$command.Dispose()}
    return ,$rows.ToArray()
}
function Get-CpqSqlSnapshot {
    param([string]$Server,[string]$Database,[int]$ModelId,[int]$VersionId)
    Assert-LedgerLocalServer $Server
    if(-not $Database -or $ModelId -le 0 -or $VersionId -le 0){throw [InvalidOperationException]::new('Declare concrete CPQ model and version identities.')}
    $builder=[Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source']=$Server;$builder['Initial Catalog']=$Database;$builder['Integrated Security']=$true;$builder['Connect Timeout']=10
    $connection=[Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    $rows=@{}
    try {
        $connection.Open();$transaction=$connection.BeginTransaction([Data.IsolationLevel]::Serializable)
        try {
            $parameters=@{'@v'=$VersionId;'@m'=$ModelId}
            $rows.CPQModel=Invoke-CpqSelect $connection $transaction 'SELECT * FROM CPQModel WHERE ModelId=@m' $parameters
            $rows.CPQModelVersion=Invoke-CpqSelect $connection $transaction 'SELECT * FROM CPQModelVersion WHERE ModelVersionId=@v' $parameters
            $rows.CPQGroup=Invoke-CpqSelect $connection $transaction 'SELECT * FROM CPQGroup WHERE GroupModelVersionId=@v ORDER BY GroupId' $parameters
            $families=@{
                CPQInput=@('InputGroupId','InputId'); CPQInputRule=@('InputRuleGroupId','InputRuleId')
                CPQBOMRule=@('BOMRuleGroupId','BOMRuleId'); CPQRouteRule=@('RouteRuleGroupId','RouteRuleId')
                CPQModelVariable=@('ModelVariableGroupId','ModelVariableId')
            }
            foreach($table in $families.Keys){
                $fk,$pk=$families[$table]
                $query="SELECT child.* FROM $table child INNER JOIN CPQGroup g ON child.$fk=g.GroupId WHERE g.GroupModelVersionId=@v ORDER BY child.$pk"
                $rows[$table]=Invoke-CpqSelect $connection $transaction $query $parameters
            }
            $families=@{
                CPQPriceRule=@('CPQPriceRuleModelVersionId','CPQPriceRuleId')
                CPQOutputRule=@('OutputRuleModelVersionId','OutputRuleId')
                CPQOutputAction=@('OutputActionModelVersionId','OutputActionId')
            }
            foreach($table in $families.Keys){
                $fk,$pk=$families[$table]
                $rows[$table]=Invoke-CpqSelect $connection $transaction "SELECT * FROM $table WHERE $fk=@v ORDER BY $pk" $parameters
            }
            # Catalogue identifiers only. Never enumerate users, cards, quotes or orders for model checks.
            $rows.EcomProducts=Invoke-CpqSelect $connection $transaction 'SELECT ProductId,ProductNumber,ProductVariantId,ProductLanguageId FROM EcomProducts ORDER BY ProductId,ProductVariantId,ProductLanguageId'
            $rows.EcomShops=Invoke-CpqSelect $connection $transaction 'SELECT ShopId FROM EcomShops ORDER BY ShopId'
            $rows.EcomLanguages=Invoke-CpqSelect $connection $transaction 'SELECT LanguageId FROM EcomLanguages ORDER BY LanguageId'
            $rows.EcomCurrencies=Invoke-CpqSelect $connection $transaction 'SELECT CurrencyCode FROM EcomCurrencies ORDER BY CurrencyCode'
            $rows.pages=Invoke-CpqSelect $connection $transaction "SELECT p.PageID,p.PageNavigationTag,p.PageItemId,i.CPQ_ModelVersionId,i.CPQ_Theme FROM Page p INNER JOIN ItemType_CPQ_Page i ON p.PageItemId=i.Id WHERE p.PageItemType=N'CPQ_Page' ORDER BY p.PageID"
            $schema=Invoke-CpqSelect $connection $transaction "SELECT TABLE_NAME,COLUMN_NAME,DATA_TYPE,CHARACTER_MAXIMUM_LENGTH,IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME LIKE 'CPQ%' OR TABLE_NAME LIKE 'ItemType_CPQ%' ORDER BY TABLE_NAME,ORDINAL_POSITION"
            $transaction.Commit()
        } finally {$transaction.Dispose()}
    } finally {$connection.Dispose()}
    return @{schemaVersion=1;modelId=$ModelId;versionId=$VersionId;complete=$true;source='sql';localOnly=$true;rows=$rows;schema=$schema}
}
