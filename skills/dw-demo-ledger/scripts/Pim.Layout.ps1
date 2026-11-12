<#
.SYNOPSIS
READ-ONLY. Product edit layout and global field placement: one table read, pure rules.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/edit-layout.md. Local integrated SQL SELECT only,
through Ledger.Sql.ps1; nothing is written and no cache flush is owed. Two handlers:
  pim-edit-layout      reads ScreenLayout, ScreenLayoutTab, ScreenLayoutGroup and ScreenLayoutEditor
                       once per run and judges one aspect of the active product edit layout.
  pim-field-placement  counts, per custom global product field, the in-scope products that carry a
                       value, once per run, and judges the share.
Every rule is a pure function over that read, so each judgement has a red control without a
database. Limits and banned names are binding arguments in the probe file, never code.
Traps encoded: a short or misspelt screen type is stored and never applied; editor system names and
tab names may carry pipes, so the free text is the last column of each row; a bit column cannot
tell "no" from "never set" and a computed field stores no value, so neither is judged; a field name
becomes a column reference only after it matched a plain identifier pattern.
.EXAMPLE
. ./Pim.Layout.ps1
Test-PimEditLayoutAspect -Aspect catch-all -Layout $layout -Build $build -Check @{} -Stored @{}
#>
#Requires -Version 7.0
# The one screen type a product edit layout must name. Any other spelling is stored and never applied.
$script:PimProductEditScreenType = 'Dynamicweb.Products.UI.Screens.ProductEditScreen'
$script:PimEditLayoutAspects = @('screen-type', 'editors-resolve', 'family-tabs', 'tabs-per-family', 'scannable', 'names', 'catch-all', 'unique-group-names', 'division')
$script:PimEditLayoutDivisions = @('role', 'task', 'lifecycle', 'source')

# Test-PimLayoutArguments (pure): the faults of a pim-edit-layout or pim-field-placement binding's
# arguments. An empty list means the limits the rule needs are stated as data.
function Test-PimLayoutArguments {
    param([Parameter(Mandatory)][string]$Handler, $Arguments)
    $faults = @()
    if ($Handler -eq 'pim-field-placement') {
        $share = $Arguments.minSharePct
        if (-not ($share -is [int] -or $share -is [long]) -or $share -lt 1 -or $share -gt 100) { $faults += 'states no minSharePct between 1 and 100' }
        return $faults
    }
    $aspect = "$($Arguments.aspect)"
    if ($script:PimEditLayoutAspects -notcontains $aspect) { return @("unknown edit-layout aspect '$aspect'") }
    if ($aspect -eq 'tabs-per-family' -and -not ([int]$Arguments.maxTabs -gt 0)) { $faults += 'states no maxTabs' }
    if ($aspect -eq 'scannable' -and -not ([int]$Arguments.maxEditorsPerGroup -gt 0 -and [int]$Arguments.maxEditorsPerTab -gt 0)) { $faults += 'states no maxEditorsPerGroup and maxEditorsPerTab' }
    if ($aspect -eq 'names') {
        if ((@($Arguments.bannedNames | Where-Object { $_ }).Count + @($Arguments.bannedPatterns | Where-Object { $_ }).Count) -eq 0) { $faults += 'lists no banned name or pattern' }
        foreach ($bp in @($Arguments.bannedPatterns)) { try { $null = [regex]::new("$bp") } catch { $faults += "has a banned pattern that is not a regular expression: '$bp'" } }
    }
    return $faults
}

# Get-PimEditLayout: every screen layout with its tabs, groups and editors, as flat lists. The free
# text (a name, an editor system name that itself carries pipes) is the LAST part of each row, so a
# pipe inside it cannot shift a column; a closing ~ keeps a trailing space from being trimmed away.
function Get-PimEditLayout {
    param([Parameter(Mandatory)][string]$Server, [Parameter(Mandatory)][string]$Database)
    $rows = {
        param([string]$Sql, [int]$Parts)
        foreach ($line in @(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query $Sql)) {
            $p = "$line".Split([char[]]'|', $Parts)
            if ($p.Count -eq $Parts) { $p[$Parts - 1] = $p[$Parts - 1] -replace '~$', ''; , $p }
        }
    }
    $layouts = @(& $rows "SELECT CAST(ScreenLayoutId AS nvarchar(20)) + N'|' + CAST(ISNULL(CAST(ScreenLayoutActive AS int), 0) AS nvarchar(2)) + N'|' + REPLACE(ISNULL(ScreenLayoutScreenType, N''), N'|', N'/') + N'|' + ISNULL(ScreenLayoutName, N'') + N'~' FROM ScreenLayout" 4 |
        ForEach-Object { [pscustomobject]@{ id = $_[0]; active = ($_[1] -eq '1'); screenType = $_[2]; name = $_[3] } })
    $tabs = @(& $rows "SELECT CAST(ScreenLayoutTabId AS nvarchar(20)) + N'|' + CAST(ISNULL(ScreenLayoutTabScreenLayoutId, 0) AS nvarchar(20)) + N'|' + CAST(ISNULL(ScreenLayoutTabOrder, 0) AS nvarchar(12)) + N'|' + ISNULL(ScreenLayoutTabName, N'') + N'~' FROM ScreenLayoutTab ORDER BY ScreenLayoutTabOrder, ScreenLayoutTabId" 4 |
        ForEach-Object { [pscustomobject]@{ id = $_[0]; layoutId = $_[1]; order = [int]$_[2]; name = $_[3] } })
    $groups = @(& $rows "SELECT CAST(ScreenLayoutGroupId AS nvarchar(20)) + N'|' + CAST(ISNULL(ScreenLayoutGroupScreenLayoutTabId, 0) AS nvarchar(20)) + N'|' + CAST(ISNULL(CAST(ScreenLayoutGroupIsCatchAll AS int), 0) AS nvarchar(2)) + N'|' + CAST(ISNULL(ScreenLayoutGroupOrder, 0) AS nvarchar(12)) + N'|' + ISNULL(ScreenLayoutGroupName, N'') + N'~' FROM ScreenLayoutGroup ORDER BY ScreenLayoutGroupOrder, ScreenLayoutGroupId" 5 |
        ForEach-Object { [pscustomobject]@{ id = $_[0]; tabId = $_[1]; catchAll = ($_[2] -eq '1'); order = [int]$_[3]; name = $_[4] } })
    $editors = @(& $rows "SELECT CAST(ISNULL(ScreenLayoutEditorScreenLayoutGroupId, N'') AS nvarchar(50)) + N'|' + ISNULL(ScreenLayoutEditorSystemName, N'') + N'~' FROM ScreenLayoutEditor ORDER BY ScreenLayoutEditorOrder, ScreenLayoutEditorId" 2 |
        ForEach-Object { [pscustomobject]@{ groupId = $_[0].Trim(); systemName = $_[1] } })
    return [pscustomobject]@{ layouts = $layouts; tabs = $tabs; groups = $groups; editors = $editors }
}

# Resolve-PimEditLayout (pure): the active layout of the product edit screen as a tree, or $null when
# there is none. tabs[] { name; groups[] { name; catchAll; editors[] { systemName; isCategory;
# wellFormed; category; field } } }. When more than one layout is active for the screen the lowest id
# is read; the screen-type aspect reports the others.
function Resolve-PimEditLayout {
    param($Layout, [string]$ScreenType = $script:PimProductEditScreenType)
    if (-not $Layout) { return $null }
    $active = @($Layout.layouts | Where-Object { $_.active -and "$($_.screenType)" -eq $ScreenType } | Sort-Object { [long]$_.id })
    if ($active.Count -eq 0) { return $null }
    $l = $active[0]
    $tabs = @()
    foreach ($t in @($Layout.tabs | Where-Object { "$($_.layoutId)" -eq "$($l.id)" })) {
        $groups = @()
        foreach ($g in @($Layout.groups | Where-Object { "$($_.tabId)" -eq "$($t.id)" })) {
            $eds = @()
            foreach ($e in @($Layout.editors | Where-Object { "$($_.groupId)" -eq "$($g.id)" })) {
                $sn = "$($e.systemName)"
                $isCat = $sn.StartsWith('CategoryFields|', [StringComparison]::OrdinalIgnoreCase)
                $p = $sn.Split('|')
                $ok = $isCat -and $p.Count -eq 4 -and $p[1] -eq 'ProductCategory' -and $p[2] -and $p[3]
                $eds += [pscustomobject]@{ systemName = $sn; isCategory = $isCat; wellFormed = [bool]$ok
                                           category = $(if ($ok) { $p[2] } else { '' }); field = $(if ($ok) { $p[3] } else { '' }) }
            }
            $groups += [pscustomobject]@{ name = "$($g.name)"; catchAll = [bool]$g.catchAll; editors = @($eds) }
        }
        $tabs += [pscustomobject]@{ name = "$($t.name)"; groups = @($groups) }
    }
    return [pscustomobject]@{ id = "$($l.id)"; name = "$($l.name)"; tabs = @($tabs) }
}

# Test-PimEditLayoutAspect (pure): one rule about the product edit layout. Returns
# @{ measured; expected; offenders[] }. Vocabulary:
#   family            a category named in the build's families[].
#   shared category   a category with fields that is NOT a declared family. Its fields belong to no
#                     family: they never make a tab mixed, they may not sit on a family's tab, and a
#                     tab that holds them counts as a shared tab for every family.
#   family tab        a tab that carries category fields of a declared family.
#   shared tab        a tab that carries no declared family's category field.
function Test-PimEditLayoutAspect {
    param(
        [Parameter(Mandatory)][ValidateSet('screen-type', 'editors-resolve', 'family-tabs', 'tabs-per-family', 'scannable', 'names', 'catch-all', 'unique-group-names', 'division')][string]$Aspect,
        $Layout,
        [Parameter(Mandatory)]$Build,
        $Check,
        [hashtable]$Stored = @{}
    )
    $screenType = if ("$($Check.screenType)") { "$($Check.screenType)" } else { $script:PimProductEditScreenType }
    $off = @()

    if ($Aspect -eq 'screen-type') {
        $active = @($Layout.layouts | Where-Object { $_.active })
        $good = @()
        foreach ($l in $active) {
            $st = "$($l.screenType)"
            $hasTab = @($Layout.tabs | Where-Object { "$($_.layoutId)" -eq "$($l.id)" }).Count -gt 0
            if ($st -eq $screenType) {
                if ($hasTab) { $good += $l } else { $off += "layout '$($l.name)' is active for the product edit screen and has no tab" }
            } elseif (-not $st.Contains('.') -or $st -match 'ProductEditScreen$') {
                $off += "layout '$($l.name)' has screen type '$st'; the product edit screen is '$screenType' and any other spelling is stored and never applied"
            }
        }
        if ($good.Count -eq 0) { $off += "no active layout with a tab has screen type '$screenType'" }
        if ($good.Count -gt 1) { $off += "$($good.Count) active layouts name the product edit screen ($(@($good | ForEach-Object { $_.name }) -join ', ')); one layout applies to a screen" }
        return @{ measured = "$($good.Count) active product edit layout(s), $($off.Count) offender(s)"; expected = 'exactly 1, 0 offenders'; offenders = $off }
    }

    $el = $null; $declared = @()
    $divisionExpected = 'editLayout states the division; the tabs it declares are the tabs of the layout'
    if ($Aspect -eq 'division') {
        $el = $Build.editLayout
        if (-not $el) {
            return @{ measured = 'editLayout not stated'; expected = $divisionExpected
                      offenders = @('the build file has no editLayout: how the shared fields are divided (role, task, lifecycle or source) and why was not stated') }
        }
        $declared = @($el.tabs | Where-Object { $_ })
        if ($declared.Count -eq 0) { return @{ measured = "division '$($el.division)' stated, no tabs declared"; expected = $divisionExpected; offenders = @() } }
    }

    $model = Resolve-PimEditLayout -Layout $Layout -ScreenType $screenType
    if (-not $model) {
        return @{ measured = 'no active product edit layout'; expected = ''
                  offenders = @("no active layout has screen type '$screenType', so nothing was measured") }
    }
    $families = @($Build.families | Where-Object { "$($_.category)" })
    $famName = @{}; foreach ($f in $families) { $famName["$($f.category)"] = "$($f.name)" }
    # Per tab: the declared families whose category fields it carries, and the count of everything else.
    $tabInfo = @()
    foreach ($t in $model.tabs) {
        $eds = @($t.groups | ForEach-Object { $_.editors })
        $fams = @($eds | Where-Object { $_.wellFormed -and $famName.ContainsKey($_.category) } | ForEach-Object { $_.category } | Sort-Object -Unique)
        $other = @($eds | Where-Object { -not ($_.wellFormed -and $famName.ContainsKey($_.category)) }).Count
        $tabInfo += [pscustomobject]@{ name = $t.name; editors = $eds; families = $fams; other = $other
                                       catchAll = (@($t.groups | Where-Object { $_.catchAll }).Count -gt 0) }
    }
    $allEditors = @($tabInfo | ForEach-Object { $_.editors })

    switch ($Aspect) {
        'editors-resolve' {
            $cat = @($allEditors | Where-Object { $_.isCategory })
            $rest = $allEditors.Count - $cat.Count
            foreach ($e in $cat) {
                if (-not $e.wellFormed) { $off += "editor '$($e.systemName)' is not of the form CategoryFields|ProductCategory|<category>|<field>" }
                elseif (-not $Stored.ContainsKey("$($e.category)|$($e.field)")) { $off += "editor '$($e.systemName)' matches no category field" }
            }
            if ($cat.Count -eq 0) { $off += 'the layout places no category field, so nothing was proved' }
            return @{ measured = "$($cat.Count) category field editor(s), $($off.Count) offender(s); $rest other editor(s) not judged"; expected = 'at least 1 category field editor, 0 offenders'; offenders = $off }
        }
        'family-tabs' {
            $placed = @{}
            foreach ($e in @($allEditors | Where-Object { $_.wellFormed })) { $placed["$($e.category)|$($e.field)"] = $true }
            $scanned = 0
            foreach ($f in $families) {
                $fields = @($Stored.Keys | Where-Object { "$_".StartsWith("$($f.category)|", [StringComparison]::OrdinalIgnoreCase) } | Sort-Object)
                if ($fields.Count -eq 0) { continue }
                $scanned++
                $missing = @($fields | Where-Object { -not $placed.ContainsKey($_) } | ForEach-Object { "$_".Split('|', 2)[1] })
                if ($missing.Count -gt 0) {
                    $list = (@($missing | Select-Object -First 5) -join ', ') + $(if ($missing.Count -gt 5) { ', ...' } else { '' })
                    $off += "family '$($f.name)': $($missing.Count) of $($fields.Count) field(s) of $($f.category) are on no tab ($list); they fall into the catch-all group"
                }
            }
            foreach ($t in $tabInfo) {
                if ($t.families.Count -ge 2) { $off += "tab '$($t.name)' mixes the fields of $($t.families.Count) families ($($t.families -join ', ')); it shows on all of them and belongs to none" }
                elseif ($t.families.Count -eq 1 -and ($t.other -gt 0 -or $t.catchAll)) {
                    $what = @(); if ($t.other -gt 0) { $what += "$($t.other) editor(s) that are not that family's" }; if ($t.catchAll) { $what += 'the catch-all group' }
                    $off += "tab '$($t.name)' carries the fields of $($t.families[0]) together with $($what -join ' and '); it shows on every product, not only on that family's"
                }
            }
            if ($scanned -eq 0) { $off += 'no declared family has a stored category field, so nothing was proved' }
            return @{ measured = "$scanned family(ies) with fields, $($model.tabs.Count) tab(s), $($off.Count) offender(s)"; expected = 'every field of every family on a tab that carries that family only'; offenders = $off }
        }
        'tabs-per-family' {
            $max = [int]$Check.maxTabs
            $shared = @($tabInfo | Where-Object { $_.families.Count -eq 0 }).Count
            $worst = $shared; $worstName = 'a product of no declared family'
            foreach ($f in $families) {
                $own = @($tabInfo | Where-Object { $_.families -contains "$($f.category)" }).Count
                $n = $shared + $own
                if ($n -gt $worst) { $worst = $n; $worstName = "$($f.name)" }
                if ($n -gt $max) { $off += "family '$($f.name)' sees $n tabs ($shared shared, $own that carry its fields); the limit is $max" }
            }
            if ($off.Count -eq 0 -and $shared -gt $max) { $off += "every product sees $shared shared tabs; the limit is $max" }
            return @{ measured = "at most $worst tab(s) on one product ($worstName)"; expected = "at most $max tabs on any family's product"; offenders = $off }
        }
        'scannable' {
            $maxG = [int]$Check.maxEditorsPerGroup; $maxT = [int]$Check.maxEditorsPerTab
            $bigG = 0; $bigT = 0
            foreach ($t in $model.tabs) {
                $n = 0
                foreach ($g in $t.groups) {
                    $c = @($g.editors).Count; $n += $c
                    if ($c -gt $bigG) { $bigG = $c }
                    if ($c -gt $maxG) { $off += "group '$($g.name)' on tab '$($t.name)' holds $c editors; the limit is $maxG" }
                }
                if ($n -gt $bigT) { $bigT = $n }
                if ($n -gt $maxT) { $off += "tab '$($t.name)' holds $n editors; the limit is $maxT" }
            }
            return @{ measured = "largest group $bigG, largest tab $bigT editor(s)"; expected = "at most $maxG per group and $maxT per tab"; offenders = $off }
        }
        'names' {
            $banned = @($Check.bannedNames | ForEach-Object { "$_".Trim() })
            $patterns = @($Check.bannedPatterns | ForEach-Object { "$_" })
            $cats = @{}; foreach ($k in $Stored.Keys) { $cats["$k".Split('|', 2)[0]] = $true }
            foreach ($f in $families) { $cats["$($f.category)"] = $true }
            $judge = {
                param([string]$What, [string]$Name, [bool]$CatchAll)
                $n = $Name.Trim()
                if (-not $n) { return "$What has no name" }
                if ($CatchAll) { return $null }
                if ($banned -contains $n) { return "$What '$n' is named after the mechanism, not after what an editor looks for" }
                if ($cats.ContainsKey($n)) { return "$What '$n' is a category id" }
                foreach ($p in $patterns) { if ($n -match "(?i)$p") { return "$What '$n' matches the banned pattern '$p'" } }
                return $null
            }
            $count = 0
            foreach ($t in $model.tabs) {
                $count++; $r = & $judge 'tab' $t.name $false; if ($r) { $off += $r }
                foreach ($g in $t.groups) { $count++; $r = & $judge "group on tab '$($t.name)'" $g.name $g.catchAll; if ($r) { $off += $r } }
            }
            return @{ measured = "$count tab and group name(s), $($off.Count) offender(s)"; expected = '0 offenders'; offenders = $off }
        }
        'catch-all' {
            $ca = @()
            foreach ($t in $model.tabs) { foreach ($g in @($t.groups | Where-Object { $_.catchAll })) { $ca += "'$($g.name)' on tab '$($t.name)'" } }
            if ($ca.Count -eq 0) { $off += 'the layout has no catch-all group: a field that is on no group has no place on the screen' }
            if ($ca.Count -gt 1) { $off += "the layout has $($ca.Count) catch-all groups ($($ca -join ', ')); one receives the fields that are placed nowhere else" }
            return @{ measured = "$($ca.Count) catch-all group(s)"; expected = 'exactly 1'; offenders = $off }
        }
        'unique-group-names' {
            $seen = @{}; $total = 0
            foreach ($t in $model.tabs) {
                foreach ($g in $t.groups) {
                    $total++
                    $k = "$($g.name)".Trim().ToLowerInvariant()
                    if (-not $seen.ContainsKey($k)) { $seen[$k] = @() }
                    $seen[$k] += $t.name
                }
            }
            foreach ($k in @($seen.Keys | Sort-Object)) {
                if ($seen[$k].Count -gt 1) { $off += "group name '$k' is used $($seen[$k].Count) times (tabs: $($seen[$k] -join ', '))" }
            }
            return @{ measured = "$total group(s), $($off.Count) duplicate name(s)"; expected = '0 duplicate names'; offenders = $off }
        }
        'division' {
            $names = @{}; foreach ($t in $tabInfo) { $names["$($t.name)".Trim()] = $t }
            $declaredNames = @{}
            foreach ($d in $declared) {
                $dn = "$($d.name)".Trim()
                # The build schema cannot refuse a tab declared twice; the rule does.
                if ($declaredNames.ContainsKey($dn)) { $off += "editLayout declares tab '$dn' twice"; continue }
                $declaredNames[$dn] = $true
                $t = $names[$dn]
                if (-not $t) { $off += "declared tab '$dn' is not on the layout"; continue }
                $for = "$($d.for)"
                if ($for -eq 'shared') {
                    if ($t.families.Count -gt 0) { $off += "tab '$dn' is declared shared and carries the fields of $($t.families -join ', ')" }
                } else {
                    $cats = @($t.editors | Where-Object { $_.wellFormed } | ForEach-Object { $_.category } | Sort-Object -Unique)
                    if ($cats -notcontains $for) { $off += "tab '$dn' is declared for $for and carries none of its fields" }
                    $others = @($cats | Where-Object { $_ -ne $for })
                    if ($others.Count -gt 0) { $off += "tab '$dn' is declared for $for and also carries the fields of $($others -join ', ')" }
                }
            }
            foreach ($t in $tabInfo) { if (-not $declaredNames.ContainsKey("$($t.name)".Trim())) { $off += "layout tab '$($t.name)' is not declared in editLayout.tabs" } }
            return @{ measured = "division '$($el.division)', $($declared.Count) declared tab(s), $($tabInfo.Count) layout tab(s), $($off.Count) offender(s)"; expected = $divisionExpected; offenders = $off }
        }
    }
}

# Get-PimGlobalFieldFill: every custom global product field (EcomProductField, not standard) with the
# number of in-scope products that carry a value in its EcomProducts column, and the number of in-scope
# products. A product is counted once, on its master row in the default language. How "a value" reads
# depends on the column: text is not empty, a number is not 0, a date is not NULL. A bit column and a
# field type with a provider come back as kind flag / computed with no count.
function Get-PimGlobalFieldFill {
    param([Parameter(Mandatory)][string]$Server, [Parameter(Mandatory)][string]$Database, [Parameter(Mandatory)]$Build)
    if ("$($Build.defaultLanguage)" -notmatch $script:PimTokenPattern) { throw [InvalidOperationException]::new('Field placement needs the build defaultLanguage.') }
    $scope = Expand-PimSql -Sql "FROM EcomProducts p WHERE p.ProductLanguageId = N'{lang}' AND ISNULL(p.ProductVariantId, N'') = N''{inScope}" -Build $Build
    $total = Invoke-Sqlcmd-Scalar -Server $Server -Database $Database -Query "SELECT COUNT(DISTINCT p.ProductId) $scope"
    $sql = "SELECT CAST(f.ProductFieldSystemName AS nvarchar(128)) COLLATE DATABASE_DEFAULT + N'|' + CASE WHEN ISNULL(t.FieldTypeProvider, N'') <> N'' THEN N'1' ELSE N'0' END + N'|' + ISNULL((SELECT TOP 1 CAST(ty.name AS nvarchar(128)) COLLATE DATABASE_DEFAULT FROM sys.columns c JOIN sys.types ty ON ty.user_type_id = c.user_type_id WHERE c.object_id = OBJECT_ID(N'EcomProducts') AND c.name COLLATE DATABASE_DEFAULT = f.ProductFieldSystemName COLLATE DATABASE_DEFAULT), N'') + N'|' FROM EcomProductField f LEFT JOIN EcomFieldType t ON t.FieldTypeId = f.ProductFieldTypeId WHERE ISNULL(f.ProductFieldIsStandard, 0) = 0"
    $fields = @()
    foreach ($line in @(Invoke-Sqlcmd-Rows -Server $Server -Database $Database -Query $sql)) {
        $p = "$line".Split('|'); if ($p.Count -lt 3) { continue }
        $name = $p[0]; $type = $p[2].ToLowerInvariant()
        $kind = if ($p[1] -eq '1') { 'computed' }
                elseif ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or -not $type) { 'unreadable' }
                elseif ($type -eq 'bit') { 'flag' }
                elseif ($type -match 'char|text') { 'text' }
                elseif ($type -match 'int|float|real|decimal|numeric|money') { 'number' }
                elseif ($type -match 'date|time') { 'date' }
                else { 'unreadable' }
        $pred = switch ($kind) {
            'text'   { "ISNULL(CAST(p.[$name] AS nvarchar(max)), N'') <> N''" }
            'number' { "ISNULL(p.[$name], 0) <> 0" }
            'date'   { "p.[$name] IS NOT NULL" }
            default  { '' }
        }
        $filled = -1
        if ($pred) { $filled = Invoke-Sqlcmd-Scalar -Server $Server -Database $Database -Query "SELECT COUNT(DISTINCT p.ProductId) $scope AND $pred" }
        $fields += [pscustomobject]@{ name = $name; kind = $kind; filled = $filled }
    }
    return [pscustomobject]@{ total = $total; fields = @($fields) }
}

# Test-PimFieldPlacement (pure): a custom global field filled on fewer than MinSharePct percent of the
# in-scope products is an offender: it is an attribute of some products and belongs in their data
# model. Declaring the field in attributes[] with an empty category does not exempt it. NOT JUDGED,
# and counted as such: flag (false is stored for "no" and for "never set") and computed (the value is
# not stored). A field whose column cannot be read is an offender: an unread field is never a pass.
function Test-PimFieldPlacement {
    param($Fill, [int]$MinSharePct = 50)
    $off = @(); $judged = 0; $skipped = 0
    $total = [int]$Fill.total
    $expected = "every custom global field filled on at least $MinSharePct% of the products in scope"
    if ($total -lt 1) { return @{ measured = '0 products in scope'; expected = $expected; offenders = @('no product is in scope, so nothing was measured') } }
    foreach ($f in @($Fill.fields)) {
        if (-not $f) { continue }
        switch ("$($f.kind)") {
            'flag' { $skipped++ }
            'computed' { $skipped++ }
            'unreadable' { $off += "global field '$($f.name)' has no readable column on EcomProducts, so its fill was not measured" }
            default {
                $judged++
                if (([long]$f.filled * 100) -lt ([long]$total * $MinSharePct)) {
                    $pct = [math]::Floor([long]$f.filled * 100 / $total)
                    $off += "global field '$($f.name)' is filled on $($f.filled) of $total products ($pct%); a field under $MinSharePct% is an attribute of some products and belongs in their data model"
                }
            }
        }
    }
    return @{ measured = "$judged custom global field(s) measured on $total product(s), $($off.Count) offender(s); $skipped checkbox or computed field(s) not judged"; expected = $expected; offenders = $off }
}

# The two handler entry points. Each reads its tables once per server and database in a run and
# returns a complete offenders observation; a malformed binding is a contract error, never a pass.
function Get-PimEditLayoutObservation {
    param($Arguments, $Build, [string]$Server, [string]$Database)
    $faults = @(Test-PimLayoutArguments -Handler 'pim-edit-layout' -Arguments $Arguments)
    if ($faults.Count) { throw "pim-edit-layout binding: $($faults -join '; ')" }
    if ($null -eq $script:LedgerPimLayout) { $script:LedgerPimLayout = @{} }
    $key = "layout|$Server|$Database"
    if (-not $script:LedgerPimLayout.ContainsKey($key)) { $script:LedgerPimLayout[$key] = Get-PimEditLayout -Server $Server -Database $Database }
    if (-not $script:LedgerStoredFields) { $script:LedgerStoredFields = Get-PimStoredField -Server $Server -Database $Database }
    $r = Test-PimEditLayoutAspect -Aspect "$($Arguments.aspect)" -Layout $script:LedgerPimLayout[$key] -Build $Build -Check $Arguments -Stored $script:LedgerStoredFields
    return @{ value = @($r.offenders).Count; complete = $true; scanned = $null; offenders = @($r.offenders); measured = "$($r.measured)" }
}
function Get-PimFieldPlacementObservation {
    param($Arguments, $Build, [string]$Server, [string]$Database)
    $faults = @(Test-PimLayoutArguments -Handler 'pim-field-placement' -Arguments $Arguments)
    if ($faults.Count) { throw "pim-field-placement binding: $($faults -join '; ')" }
    if ($null -eq $script:LedgerPimLayout) { $script:LedgerPimLayout = @{} }
    $key = "fill|$Server|$Database"
    if (-not $script:LedgerPimLayout.ContainsKey($key)) { $script:LedgerPimLayout[$key] = Get-PimGlobalFieldFill -Server $Server -Database $Database -Build $Build }
    $r = Test-PimFieldPlacement -Fill $script:LedgerPimLayout[$key] -MinSharePct ([int]$Arguments.minSharePct)
    return @{ value = @($r.offenders).Count; complete = $true; scanned = $null; offenders = @($r.offenders); measured = "$($r.measured)" }
}
