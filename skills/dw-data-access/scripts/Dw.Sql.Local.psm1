<#
.SYNOPSIS
    WRITES: nothing on import. The one local-only SQL non-query path — the
    write half of what Dw.Api.psm1 deliberately ships only as reads.

.DESCRIPTION
    `Dw.Api.psm1` owns `Get-DwSqlRows` / `Get-DwSqlScalar` and ships no SQL
    write path at all. Two scripts in this folder need one (the scheduled-task
    row that no Management API command writes, and the SQL-then-flush recipe),
    so the non-query lives here, in its own small file, rather than widening
    the shared module.

    Same refusal as the read helpers, made explicit because this one writes:
    SQL is LOCAL INSTALLS ONLY. A hosted install has no SQL surface, and no
    remote SQL path exists by design. `Assert-DwSqlLocal` parses the server
    out of the connection string and throws on anything that is not a local
    token (`.`, `(local)`, `(localdb)\...`, `localhost`, `127.0.0.1`, `::1`,
    or this machine's own name), so a connection string pointed at a remote
    instance fails before a statement runs.

    Ordering rule this module cannot enforce and every caller owes: all rung
    1-2 writes first, then the SQL touch-up, then the flush, and nothing
    re-saves the entity afterwards — the next API save of a cached entity
    writes DW's cached model back over what SQL wrote behind it. The
    per-mutation table is in
    dw-data-access/references/cache-invalidation.md.

    Owning reference: dw-data-access/references/management-api-and-sql.md.

.EXAMPLE
    Import-Module (Join-Path $PSScriptRoot 'Dw.Sql.Local.psm1') -Force -ErrorAction Stop
    Invoke-DwSqlNonQuery -Sql 'UPDATE Page SET PageActive = 1 WHERE PageId = 7'
#>
#Requires -Version 7.0
param()

$ErrorActionPreference = 'Stop'

# Server tokens that name the machine this script runs on. Anything else is a
# remote instance and is refused.
$script:LocalServerTokens = @('.', '(local)', 'localhost', '127.0.0.1', '::1', $env:COMPUTERNAME)

function Get-DwLocalSqlConnectionString {
    <#
    .SYNOPSIS
        READ-ONLY. Resolves the local SQL connection string.
    .DESCRIPTION
        Explicit parameter, then $env:DW_SQL_CONNECTION, then fail with the
        one-liner that fixes it — the same order Dw.Api.psm1 uses, minus the
        Connect-Dw session state this module does not share.
    .PARAMETER ConnectionString
        Explicit override.
    .EXAMPLE
        Get-DwLocalSqlConnectionString
    #>
    [CmdletBinding()]
    param([string]$ConnectionString)
    if ($ConnectionString) { return $ConnectionString }
    if ($env:DW_SQL_CONNECTION) { return $env:DW_SQL_CONNECTION }
    throw ("No SQL connection. Pass -ConnectionString or set `$env:DW_SQL_CONNECTION. " +
        "SQL is LOCAL-ONLY: a hosted install has no SQL surface, and no remote SQL path " +
        "exists by design.")
}

function Assert-DwSqlLocal {
    <#
    .SYNOPSIS
        READ-ONLY. Throws unless the connection string names a local server.
    .DESCRIPTION
        Reads the Server / Data Source key and compares it against the local
        tokens, ignoring a `\INSTANCE` suffix and a `,PORT` suffix. Called by
        every write in this module so a remote target cannot be reached by
        accident.
    .PARAMETER ConnectionString
        The connection string to inspect.
    .EXAMPLE
        Assert-DwSqlLocal -ConnectionString $env:DW_SQL_CONNECTION
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ConnectionString)
    $m = [regex]::Match($ConnectionString, '(?i)\b(?:server|data source|addr|address|network address)\s*=\s*([^;]+)')
    if (-not $m.Success) {
        throw 'Connection string names no Server / Data Source — refusing to run SQL against an unknown host.'
    }
    $server = $m.Groups[1].Value.Trim()
    # Strip a named-instance and a port suffix before comparing; `(localdb)\x`
    # keeps its prefix, which is matched on its own below.
    $bare = ($server -split ',')[0].Trim()
    $host_ = ($bare -split '\\')[0].Trim()
    $isLocal = ($script:LocalServerTokens | Where-Object { $_ -and $_ -eq $host_ }).Count -gt 0
    if (-not $isLocal -and $bare -match '(?i)^\(localdb\)') { $isLocal = $true }
    if (-not $isLocal) {
        throw ("Refusing to run SQL against '$server': SQL is LOCAL INSTALLS ONLY. " +
            "A hosted install has no SQL surface — use the Management API (rung 2) instead.")
    }
    $true
}

function Invoke-DwSqlNonQuery {
    <#
    .SYNOPSIS
        WRITES: runs a SQL non-query statement on the LOCAL install.
    .DESCRIPTION
        ExecuteNonQuery inside one transaction, with named parameters bound
        through SqlParameter (never string-built SQL). Returns the number of
        rows affected. The caller owes the cache flush — this module never
        guesses one.
    .PARAMETER Sql
        The statement to run.
    .PARAMETER Parameters
        Hashtable of @name -> value bound as SqlParameters. A $null value is
        sent as DBNull (the TaskParentId NULL-not-0 rule depends on this).
    .PARAMETER ConnectionString
        Overrides $env:DW_SQL_CONNECTION.
    .EXAMPLE
        Invoke-DwSqlNonQuery -Sql 'UPDATE Task SET TaskActive = 0 WHERE TaskID = @id' -Parameters @{ id = 12 }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [hashtable]$Parameters,
        [string]$ConnectionString
    )
    $conn = Get-DwLocalSqlConnectionString -ConnectionString $ConnectionString
    Assert-DwSqlLocal -ConnectionString $conn | Out-Null
    $connection = [System.Data.SqlClient.SqlConnection]::new($conn)
    try {
        $connection.Open()
        $tx = $connection.BeginTransaction()
        try {
            $command = $connection.CreateCommand()
            $command.Transaction = $tx
            $command.CommandText = $Sql
            $command.CommandTimeout = 300
            if ($Parameters) {
                foreach ($key in $Parameters.Keys) {
                    $value = $Parameters[$key]
                    if ($null -eq $value) { $value = [System.DBNull]::Value }
                    $command.Parameters.AddWithValue("@$key", $value) | Out-Null
                }
            }
            $affected = $command.ExecuteNonQuery()
            $tx.Commit()
            $affected
        }
        catch { $tx.Rollback(); throw }
    }
    finally { $connection.Dispose() }
}

function Invoke-DwSqlScalarWrite {
    <#
    .SYNOPSIS
        WRITES: runs a SQL statement on the LOCAL install and returns one value.
    .DESCRIPTION
        The INSERT ... ; SELECT SCOPE_IDENTITY() case: a write whose result is
        the new id. Same transaction, parameters and local-only refusal as
        Invoke-DwSqlNonQuery.
    .PARAMETER Sql
        The statement to run.
    .PARAMETER Parameters
        Hashtable of @name -> value; $null becomes DBNull.
    .PARAMETER ConnectionString
        Overrides $env:DW_SQL_CONNECTION.
    .EXAMPLE
        Invoke-DwSqlScalarWrite -Sql 'INSERT INTO Task (TaskName) VALUES (@n); SELECT CAST(SCOPE_IDENTITY() AS int)' -Parameters @{ n = 'x' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [hashtable]$Parameters,
        [string]$ConnectionString
    )
    $conn = Get-DwLocalSqlConnectionString -ConnectionString $ConnectionString
    Assert-DwSqlLocal -ConnectionString $conn | Out-Null
    $connection = [System.Data.SqlClient.SqlConnection]::new($conn)
    try {
        $connection.Open()
        $tx = $connection.BeginTransaction()
        try {
            $command = $connection.CreateCommand()
            $command.Transaction = $tx
            $command.CommandText = $Sql
            $command.CommandTimeout = 300
            if ($Parameters) {
                foreach ($key in $Parameters.Keys) {
                    $value = $Parameters[$key]
                    if ($null -eq $value) { $value = [System.DBNull]::Value }
                    $command.Parameters.AddWithValue("@$key", $value) | Out-Null
                }
            }
            $result = $command.ExecuteScalar()
            $tx.Commit()
            if ($result -is [System.DBNull]) { $null } else { $result }
        }
        catch { $tx.Rollback(); throw }
    }
    finally { $connection.Dispose() }
}

Export-ModuleMember -Function @(
    'Get-DwLocalSqlConnectionString', 'Assert-DwSqlLocal',
    'Invoke-DwSqlNonQuery', 'Invoke-DwSqlScalarWrite'
)
