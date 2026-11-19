<#
.SYNOPSIS
WRITES: the one MCP tool call or Management API command a recipe binding names, when the runner applies.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/recipes.md. Called only by the step engine, only with -Apply, and only for an operation on recipeWriteTools or recipeAdminCommands in assets/handlers.json (checked again here, before the call). A recipe never writes through SQL. A write's own status is not its evidence: an error result or a refusal stops the item, and a success is still read back by the step engine. No argument value, token or response body is printed.
.EXAMPLE
. ./Recipe.Write.ps1
#>
#Requires -Version 7.0
function Invoke-RecipeWrite {
    # -Arguments: arguments a scan step already expanded and batched; otherwise the binding's own, expanded here.
    param($Binding, [string]$Action, $Context, $Run, $Arguments)
    $operation = [string]$Binding[$Action].operation
    $fault = Get-RecipeSurfaceFault $Binding $operation 'write' $Run.cap $Run.registry
    if ($fault) { throw (New-RecipeFault "Write refused before the call: $fault.") }
    $arguments = if ($null -ne $Arguments) { $Arguments } else { Expand-RecipeValue $Binding[$Action].arguments $Context }
    if ($Binding.surface -eq 'mcp') {
        $result = Invoke-RecipeMcpCall $operation $arguments $Run.cap 120 -AllowText
        # A batch save answers per-item counts; a failed item is a failed write whatever the call status says.
        $failed = Get-RecipeValue $result 'failed'
        if ($failed.found -and (Test-RecipeNumber $failed.value) -and $failed.value -gt 0) { throw (New-RecipeFailure "MCP $operation reported $($failed.value) failed item(s).") }
        return
    }
    if ($Binding.surface -eq 'admin-api') {
        $response = ConvertTo-RecipeData (Invoke-DwApi $operation -Body $arguments)
        # A refusal arrives as HTTP 200 with a status other than ok ("invalid", "notFound").
        $status = Get-RecipeValue $response 'status'
        if ($status.found -and $null -ne $status.value -and [string]$status.value -ne 'ok') { throw (New-RecipeFailure "Management API $operation answered status '$($status.value)'.") }
        return
    }
    throw (New-RecipeFault "Surface $($Binding.surface) cannot write in a recipe.")
}
