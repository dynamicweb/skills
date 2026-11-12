<#
.SYNOPSIS
READ-ONLY. Parse CPQ JSON and inspect references and condition syntax, never evaluate rules.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/cpq-observations.md. Definitions only.
Unknown dialects are refused; defaults and variable values must be treated as literals.
.EXAMPLE
. ./Cpq.Json.ps1
#>
#Requires -Version 7.0
function Read-CpqValue {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return ,@() }
    $doc=[Text.Json.JsonDocument]::Parse($Text)
    function Test-CpqKeys($Node) {
        if ($Node.ValueKind -eq 'Object') {
            $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($p in $Node.EnumerateObject()) {
                if (-not $keys.Add($p.Name)) { throw [IO.InvalidDataException]::new('Duplicate JSON property.') }
                Test-CpqKeys $p.Value
            }
        } elseif ($Node.ValueKind -eq 'Array') { foreach ($v in $Node.EnumerateArray()) { Test-CpqKeys $v } }
    }
    try { Test-CpqKeys $doc.RootElement } finally { $doc.Dispose() }
    return ,(ConvertFrom-Json -InputObject $Text -AsHashtable -Depth 100 -NoEnumerate)
}
function ConvertTo-CpqObservationJson {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [Collections.IDictionary]) {
        [string[]]$keys=@($Value.Keys);[Array]::Sort($keys,[StringComparer]::Ordinal)
        return '{'+((@($keys | ForEach-Object { (ConvertTo-Json $_ -Compress)+':'+(ConvertTo-CpqObservationJson $Value[$_]) })) -join ',')+'}'
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        return '['+((@(foreach($v in $Value){ConvertTo-CpqObservationJson $v})) -join ',')+']'
    }
    return ConvertTo-Json -InputObject $Value -Compress -Depth 100
}
function Assert-CpqReferences {
    param($Value,$Inputs,$Variables,$Groups)
    if ($Value -is [Collections.IDictionary]) {
        foreach($k in $Value.Keys){Assert-CpqReferences $k $Inputs $Variables $Groups;Assert-CpqReferences $Value[$k] $Inputs $Variables $Groups}
    } elseif ($Value -is [array]) { foreach($v in $Value){Assert-CpqReferences $v $Inputs $Variables $Groups} }
    elseif ($Value -is [string]) {
        foreach($m in [regex]::Matches($Value,'(?i)(forminput|var|group)\[([^\]]+)\]')) {
            $name=$m.Groups[2].Value.Split('.')[0]
            $names=switch($m.Groups[1].Value.ToLowerInvariant()) {'forminput' {$Inputs} 'var' {@($Variables)+@('bom_total_sell','bom_total_cost')} 'group' {$Groups}}
            if ($name -notin $names) { throw [IO.InvalidDataException]::new('Unresolved version-local reference.') }
        }
        $remaining=[regex]::Replace($Value,'(?i)(forminput|var|group)\[[^\]]+\]','')
        if ($remaining -match '(?i)(forminput|var|group)\[') { throw [IO.InvalidDataException]::new('Malformed reference.') }
    }
}
function Assert-CpqConditionNode {
    param($Node,$Inputs,$Variables,$Groups,[int]$Depth=0)
    if($Depth -gt 40){throw [IO.InvalidDataException]::new('Condition nesting exceeds the supported limit.')}
    if($Node -is [Collections.IDictionary]) {
        if($Node.group_operator -cnotin @('AND','OR')){throw [IO.InvalidDataException]::new('Condition group requires uppercase AND or OR.')}
        $lists=@($Node.Keys | Where-Object {$_ -cne 'group_operator'})
        if(-not $lists.Count -or @($lists | Where-Object {$_ -cnotin @('and','or','nor','nand')}).Count){throw [IO.InvalidDataException]::new('Unknown condition group shape.')}
        foreach($list in $lists){
            if($Node[$list] -isnot [array] -or $Node[$list].Count -eq 0){throw [IO.InvalidDataException]::new('Empty condition group.')}
            foreach($child in $Node[$list]){Assert-CpqConditionNode $child $Inputs $Variables $Groups ($Depth+1)}
        }
    } elseif($Node -is [array] -and $Node.Count -eq 3 -and $Node[1] -is [string]) {
        $ops=@('eq','in','neq','ne','not equal','nin','notin','not in','gt','lt','gte','lte','hasvalue','contains','not contain','startswith','start with','endswith','end with')
        if($Node[1] -cnotin $ops){throw [IO.InvalidDataException]::new('Unsupported condition operator.')}
        if($Node[0] -is [Collections.IDictionary] -or $Node[0] -is [array]){throw [IO.InvalidDataException]::new('Invalid tuple operand.')}
        Assert-CpqReferences $Node $Inputs $Variables $Groups
    } else {throw [IO.InvalidDataException]::new('Expected a three-element tuple or explicit group.')}
}
function Assert-CpqConditions {
    param([AllowNull()][string]$Text,$Inputs,$Variables,$Groups)
    $node=Read-CpqValue $Text
    if($node -is [array] -and $node.Count -eq 0){return}
    if($node -is [array] -and -not($node.Count -eq 3 -and $node[1] -is [string])) {
        foreach($child in $node){Assert-CpqConditionNode $child $Inputs $Variables $Groups}
    } else {Assert-CpqConditionNode $node $Inputs $Variables $Groups}
}
