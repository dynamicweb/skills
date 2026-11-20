<#
.SYNOPSIS
READ-ONLY. Recipe paths and token substitution; definitions only. Comparison, matching and binding selection are in Recipe.Match.ps1.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. Dot-sourced after Ledger.Core.ps1 (Read-LedgerJson). A path is dotted members with [n] or [*]; a token is {root.path} with the roots input, item, parent, step, found, build and secret, an optional |<JSON literal or input path> default, an optional text: prefix that makes the value text, and base64: or bytes: prefixes that read the file the value names relative to the input file (never outside its folder). Whole-value substitution keeps the value's type; a token inside text becomes text. Nothing in a recipe is evaluated as code: comparisons are equals, contains and exists only. A secret is read from DW_RECIPE_SECRETS and never printed.
.EXAMPLE
. ./Recipe.Core.ps1
#>
#Requires -Version 7.0
function New-RecipeFault([string]$Message) {
    # Nothing could be observed or done (OPEN): the text names paths and tokens, never a value, so it may be printed.
    return [InvalidOperationException]::new($Message)
}
function New-RecipeFailure([string]$Message) {
    # The target answered and the answer is a failure (FAIL); the text names the operation, never a response body.
    return [ApplicationException]::new($Message)
}
function Resolve-RecipeFile {
    # A recipe is named by id (users.accounts -> assets/recipes/users/users.accounts.json) or by path.
    param([string]$Recipe, [string]$Assets)
    if (Test-Path -LiteralPath $Recipe -PathType Leaf) { return (Resolve-Path -LiteralPath $Recipe).Path }
    if ($Recipe -cnotmatch '^([a-z][a-z0-9-]*)\.[a-z0-9-]+$') { throw (New-RecipeFault "Recipe '$Recipe' is neither a file nor a recipe id such as users.accounts.") }
    $path = Resolve-LedgerPath (Join-Path $Assets 'recipes') ($Matches[1] + '/' + $Recipe + '.json')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw (New-RecipeFault "No recipe '$Recipe': assets/recipes/$($Matches[1])/$Recipe.json does not exist. Find-DwRecipe.ps1 lists the recipes.") }
    return $path
}
function Get-RecipeMember {
    # One member by exact name, else by a unique case-insensitive name; @{found; value}.
    param($Object, [string]$Name)
    if ($Object -isnot [Collections.IDictionary]) { return @{found = $false; value = $null} }
    if ($Object.Contains($Name)) { return @{found = $true; value = $Object[$Name]} }
    $hits = @($Object.Keys | Where-Object { [string]::Equals([string]$_, $Name, [StringComparison]::OrdinalIgnoreCase) })
    if ($hits.Count -eq 1) { return @{found = $true; value = $Object[$hits[0]]} }
    return @{found = $false; value = $null}
}
function Get-RecipeValue {
    # A dotted path with optional [n] indexes; '$' is the object itself. @{found; value}.
    # A [*] level maps the rest of the path over every element (the values of an object) and returns them as one
    # list; an element without the rest is left out, and a list the rest returns is flattened into it (rows of rows).
    param($Object, [string]$Path)
    if ([string]::IsNullOrEmpty($Path) -or $Path -eq '$') { return @{found = $true; value = $Object} }
    $parts = $Path.Split('.')
    $current = $Object
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($parts[$i] -notmatch '^(?<name>[^\[\]]+)(\[(?<index>\d+|\*)\])?$') { throw (New-RecipeFault "Path '$Path' is not a dotted member path.") }
        $index = $Matches['index']
        $member = Get-RecipeMember $current $Matches['name']
        if (-not $member.found) { return @{found = $false; value = $null} }
        $current = $member.value
        if ($index -eq '*') {
            $elements = if ($current -is [Collections.IDictionary]) { @($current.Values) } elseif ($current -is [Collections.IList]) { @($current) } else { return @{found = $false; value = $null} }
            $rest = ($parts | Select-Object -Skip ($i + 1)) -join '.'
            $out = [Collections.Generic.List[object]]::new()
            foreach ($element in $elements) {
                if (-not $rest) { $out.Add($element); continue }
                $value = Get-RecipeValue $element $rest
                if (-not $value.found) { continue }
                if ($value.value -is [Collections.IList]) { foreach ($x in $value.value) { $out.Add($x) } } else { $out.Add($value.value) }
            }
            return @{found = $true; value = $out.ToArray()}
        }
        if ($index) {
            $at = [int]$index
            if ($current -isnot [Collections.IList] -or $at -ge $current.Count) { return @{found = $false; value = $null} }
            $current = $current[$at]
        }
    }
    return @{found = $true; value = $current}
}
function Get-RecipeItems {
    # forEach "a[*].b[*]": every b with its enclosing a as parent. No forEach: the section is the one item.
    # (The parameter is not named ForEach: inside a foreach loop that name is the automatic enumerator.)
    param($Section, [string]$Path)
    if (-not $Path) { return , @(@{item = $Section; parent = $null}) }
    $contexts = @(@{item = $Section; parent = $null; root = $true})
    foreach ($part in $Path.Split('.')) {
        $all = $part.EndsWith('[*]'); $name = $part.Replace('[*]', '')
        $next = [Collections.Generic.List[object]]::new()
        foreach ($c in $contexts) {
            $member = Get-RecipeMember $c.item $name
            if (-not $member.found -or $null -eq $member.value) { continue }
            if (-not $all) { $next.Add(@{item = $member.value; parent = $c.parent; root = $c.root}); continue }
            # The enclosing item of a [*] level is its parent; the section itself is nobody's parent.
            # A [*] over an object (a product's specs) walks its entries as {key, value} items.
            $elements = if ($member.value -is [Collections.IDictionary]) { @(foreach ($k in @($member.value.Keys)) { @{key = [string]$k; value = $member.value[$k]} }) } else { @($member.value) }
            foreach ($x in $elements) { $next.Add(@{item = $x; parent = $(if ($c.root) { $null } else { $c.item }); root = $false}) }
        }
        $contexts = $next.ToArray()
    }
    return , @($contexts)
}
function Read-RecipeSecrets {
    # DW_RECIPE_SECRETS: a JSON object {referenceKey: value}. The fault names the shape only.
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @{} }
    try { $parsed = ConvertFrom-Json -InputObject $Text -AsHashtable } catch { $parsed = $null }
    if ($parsed -isnot [Collections.IDictionary] -or @($parsed.Values | Where-Object { $_ -isnot [string] -or $_ -eq '' }).Count) {
        throw (New-RecipeFault 'Runner input: DW_RECIPE_SECRETS is not a JSON object of {referenceKey: "value"}.')
    }
    return $parsed
}
function Resolve-RecipeRootPath {
    # input.x, item.x, parent.x, found.x, build.x, row.x (the row a scan or prune step writes) and scope (the owner a
    # prune step reads for) against the context; @{found; value}.
    param([string]$Path, $Context)
    if ($Path -notmatch '^(?<root>input|item|parent|found|build|row|scope)(\.(?<rest>.+))?$') { throw (New-RecipeFault "Token path '$Path' has an unknown root.") }
    $base = switch ($Matches['root']) { 'input' { $Context.input } 'item' { $Context.item } 'parent' { $Context.parent } 'found' { $Context.found } 'build' { $Context.build } 'row' { $Context.row } 'scope' { $Context.scope } }
    if ($null -eq $base) { return @{found = $false; value = $null} }
    return Get-RecipeValue $base $Matches['rest']
}
function Resolve-RecipeInputFile {
    # A file the input names by a path relative to the input file; never a rooted path or one that leaves that folder.
    param([string]$Path, $Context)
    if (-not $Context.inputDir) { throw (New-RecipeFault 'Runner input: a file token needs the input file''s folder.') }
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path)) { throw (New-RecipeFault "Runner input: file '$Path' is not a path relative to the input file.") }
    $root = [IO.Path]::GetFullPath($Context.inputDir).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath((Join-Path $root $Path))
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw (New-RecipeFault "Runner input: file '$Path' is outside the input file's folder.") }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw (New-RecipeFault "Runner input: file '$Path' does not exist beside the input file.") }
    return $full
}
function Resolve-RecipeToken {
    # The value of one token body; throws a fault that names the token when it does not resolve.
    param([string]$Body, $Context)
    # text: makes the value text, for the commands whose ids are strings (UsersAddToGroups Ids answers 500 on numbers).
    if ($Body.StartsWith('text:')) { $value = Resolve-RecipeToken $Body.Substring(5) $Context; return $(if ($null -eq $value) { $null } else { [string]$value }) }
    # replaced: is the value with every occurrence of the scan's text (ignoring case) replaced, for a scan step's write.
    if ($Body.StartsWith('replaced:')) {
        if (-not $Context.replace) { throw (New-RecipeFault "Token {$Body} is used outside a scan step.") }
        $value = [string](Resolve-RecipeToken $Body.Substring(9) $Context)
        return $value.Replace([string]$Context.replace.text, [string]$Context.replace.with, [StringComparison]::OrdinalIgnoreCase)
    }
    # base64: and bytes: read the file the value names, relative to the input file: its content for an upload, its size to compare.
    if ($Body -match '^(?<kind>base64|bytes):(?<rest>.+)$') {
        $kind = $Matches['kind']
        $file = Resolve-RecipeInputFile ([string](Resolve-RecipeToken $Matches['rest'] $Context)) $Context
        if ($kind -eq 'bytes') { return [long](Get-Item -LiteralPath $file).Length }
        return [Convert]::ToBase64String([IO.File]::ReadAllBytes($file))
    }
    # basename: the file name of a file the input names, for a target that stores the file under its own name.
    if ($Body -match '^basename:(?<rest>.+)$') { return [IO.Path]::GetFileName((Resolve-RecipeInputFile ([string](Resolve-RecipeToken $Matches['rest'] $Context)) $Context)) }
    $path = $Body; $default = $null; $hasDefault = $false
    $bar = $Body.IndexOf('|')
    if ($bar -ge 0) {
        $path = $Body.Substring(0, $bar); $hasDefault = $true
        $literal = $Body.Substring($bar + 1)
        # A default is a JSON literal, or an input path read only when the default applies ({step.models[item.parent].name|item.name}).
        if ($literal -match '^(input|item|parent|build)(\.[A-Za-z0-9_]+(\[(\d+|\*)\])?)+$') { $value = Resolve-RecipeRootPath $literal $Context; $default = if ($value.found) { $value.value } else { $null } }
        else { try { $default = ConvertFrom-Json -InputObject $literal -AsHashtable -NoEnumerate } catch { throw (New-RecipeFault "Token {$Body} has a default that is neither a JSON literal nor an input path.") } }
    }
    if ($path -match '^secret\.(?<ref>.+)$') {
        $ref = Resolve-RecipeRootPath $Matches['ref'] $Context
        if (-not $ref.found -or [string]::IsNullOrWhiteSpace([string]$ref.value)) {
            # No reference in the input (a user without a password): the default, never a guessed secret.
            if ($hasDefault) { return $default }
            throw (New-RecipeFault "Runner input: token {$Body} names no secret reference.")
        }
        if (-not $Context.secrets.Contains([string]$ref.value)) { throw (New-RecipeFault "Runner input: secret reference '$($ref.value)' is not a key of DW_RECIPE_SECRETS.") }
        return $Context.secrets[[string]$ref.value]
    }
    if ($path -match '^step\.(?<step>[a-z][a-z0-9-]*)(\[(?<key>(?:[^\[\]]|\[(?:\*|\d+)\])+)\])?\.(?<field>.+)$') {
        $field = $Matches['field']; $stepId = $Matches['step']; $key = $Context.key
        if ($Matches['key'] -eq '*') {
            # Every value the step produced under that name, over all its keys: what this run found or wrote (a retire keeps them).
            $all = $Context.results[$stepId]
            return , @(if ($all) { foreach ($r in @($all.Values)) { if ($r.values) { $v = Get-RecipeValue $r.values $field; if ($v.found -and $null -ne $v.value) { $v.value } } } })
        }
        if ($Matches['key']) {
            $parts = [Collections.Generic.List[string]]::new()
            foreach ($p in $Matches['key'].Split(',')) {
                $v = Resolve-RecipeRootPath $p.Trim() $Context
                if ($v.found -and $v.value -is [Collections.IList]) {
                    # One key path that is a list ({step.states[item.next[*]].id}) maps to the list of the values of those keys.
                    if ($Matches['key'].Contains(',')) { throw (New-RecipeFault "Token {$Body}: a list-valued key cannot be combined with another key path.") }
                    $one = $Body.Substring(0, $Body.IndexOf('[')) + '[item].' + $field
                    return , @(foreach ($element in $v.value) { $inner = $Context.Clone(); $inner.item = $element; Resolve-RecipeToken $one $inner })
                }
                if ($v.found -and $null -ne $v.value) { $parts.Add([string]$v.value); continue }
                # The default applies only when the key itself is absent, never when a named result is missing.
                if ($hasDefault) { return , $default }
                throw (New-RecipeFault "Runner input: token {$Body} has no key value.")
            }
            $key = $parts -join '/'
        }
        $results = $Context.results[$stepId]
        $prior = if ($results -and $results.Contains($key)) { $results[$key] }
        # The object this value comes from does not exist yet (a verify run reports the item as one apply would create), or a layer delivered it and it was not read under its own keys (the dependant is the layer's too).
        if ($prior.state -in @('WOULD-CREATE', 'BLOCKED') -or ($prior.state -eq 'DELIVERED' -and -not ($prior.values -and (Get-RecipeValue $prior.values $field).found))) {
            $missing = [Collections.Generic.KeyNotFoundException]::new("depends on $stepId '$key', which " + $(if ($prior.state -eq 'DELIVERED') { 'a layer delivered under its own keys' } else { "is $($prior.state.ToLowerInvariant())" })); $missing.Data['delivered'] = $prior.state -eq 'DELIVERED'; throw $missing }
        if (-not $results -or -not $results.Contains($key) -or -not $results[$key].values) { throw (New-RecipeFault "Runner input: token {$Body}: step '$stepId' produced no value for '$key'.") }
        $value = Get-RecipeValue $results[$key].values $field
        if (-not $value.found) { throw (New-RecipeFault "Runner input: token {$Body}: step '$stepId' produced no '$field'.") }
        # The comma keeps a one-element list a list (a return unrolls it).
        return , $value.value
    }
    $value = Resolve-RecipeRootPath $path $Context
    if ($value.found -and $null -ne $value.value) { return , $value.value }
    if ($hasDefault) { return , $default }
    throw (New-RecipeFault "Runner input: token {$Body} does not resolve.")
}
function Expand-RecipeValue {
    # Deep copy with every token substituted. A whole-value token keeps its type (numbers stay numbers).
    # Text around one list-valued token ({item.specFields[*].key}) fans out: one text per element, and in a list
    # those texts take the template's place, so "ProductCategory|{step.categories.id}|{item.specFields[*].key}" is a list.
    param($Value, $Context)
    if ($Value -is [string]) {
        if ($Value -match '^\{(?<body>[^{}]+)\}$') { return , (Resolve-RecipeToken $Matches['body'] $Context) }
        $tokens = @([regex]::Matches($Value, '\{(?<body>[^{}]+)\}'))
        if (-not $tokens.Count) { return $Value }
        $values = @(foreach ($m in $tokens) { , (Resolve-RecipeToken $m.Groups['body'].Value $Context) })
        $lists = @(for ($i = 0; $i -lt $values.Count; $i++) { if ($values[$i] -is [Collections.IList]) { $i } })
        if ($lists.Count -gt 1) { throw (New-RecipeFault "Text '$Value' holds more than one list-valued token.") }
        $render = {
            param($Element)
            $text = [Text.StringBuilder]::new(); $at = 0
            for ($i = 0; $i -lt $tokens.Count; $i++) {
                $part = if ($lists.Count -and $i -eq $lists[0]) { $Element } else { $values[$i] }
                $null = $text.Append($Value.Substring($at, $tokens[$i].Index - $at)).Append([string]$part)
                $at = $tokens[$i].Index + $tokens[$i].Length
            }
            $text.Append($Value.Substring($at)).ToString()
        }
        if (-not $lists.Count) { return (& $render $null) }
        return , @(foreach ($element in $values[$lists[0]]) { & $render $element })
    }
    if ($Value -is [Collections.IDictionary]) {
        # A hashtable, because the shared transport takes MCP arguments as one.
        $copy = @{}
        foreach ($k in $Value.Keys) { $copy[$k] = Expand-RecipeValue $Value[$k] $Context }
        return $copy
    }
    if ($Value -is [Collections.IList]) {
        return , @(foreach ($x in $Value) {
            $expanded = Expand-RecipeValue $x $Context
            # A text element that fanned out is spliced in; any other value stays one element.
            if ($x -is [string] -and $expanded -is [Collections.IList] -and $x -notmatch '^\{[^{}]+\}$') { $expanded } else { , $expanded }
        })
    }
    return $Value
}
