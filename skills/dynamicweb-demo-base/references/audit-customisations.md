# Audit customisations -- end-of-phase verifier

Audit recipe for the per-demo `CUSTOMISATIONS.md` ledger. Output is **paste-ready** slide content for the demo's closing customisation-budget review. The format IS the slide -- do not embellish.

This is the verifier for **the customisations-ledger preflight**: the write-time preflight in `references/customisations.md` produces ledger rows; this recipe verifies that the file count under `Dynamicweb.Host.Suite/Controllers/` matches the ledger row count and that the customisation budget held.

## 1. When to run

- **End of every customer-demo phase boundary** -- run from the solution root. Eyeball the output. If `TARGET MISSED`, walk the difference between `Controllers/` files and ledger rows before declaring the phase complete.
- **Final review at the demo's closing customisation-budget slide.** The output goes directly into the pitch deck. (The exact phase / requirement-ID is project-specific; see the demo's `.planning/` for the closing-budget milestone.)

## 2. Recipe

Run this from the solution root (one level above `Dynamicweb.Host.Suite/`). The here-string output is paste-ready:

```powershell
$controllers = Get-ChildItem -Recurse -Path "Dynamicweb.Host.Suite/Controllers/" -Filter "*Controller.cs" -ErrorAction SilentlyContinue
$controllerCount = ($controllers | Measure-Object).Count

$ledgerLines = (Get-Content "CUSTOMISATIONS.md" -ErrorAction SilentlyContinue) |
  Where-Object { $_ -match '^\|\s*\d{4}-\d{2}-\d{2}' }   # date-prefixed rows only
$ledgerCount = ($ledgerLines | Measure-Object).Count

# Paste-ready output
@"
## Customisation budget -- <demo-name>

- **Rows logged in CUSTOMISATIONS.md:** $ledgerCount
- **Files under Dynamicweb.Host.Suite/Controllers/:** $controllerCount
- **Target:** $ledgerCount rows logged, 0 files under Controllers/
- **Status:** $(if ($controllerCount -eq 0) { 'TARGET MET ✓' } else { 'TARGET MISSED -- review each file' })
"@
```

## 3. Slide-content contract

The here-string output goes directly into the demo's closing customisation-budget slide. Format IS the slide -- do not embellish, do not reformat. The slide reader sees `TARGET MET ✓` or `TARGET MISSED -- review each file` as a hard pass/fail signal.

Replace `<demo-name>` in the heading with the actual demo folder name when pasting into the slide. The recipe deliberately does not auto-substitute -- the slide author knows the customer name and types it once.

## 4. Interpreting the output

- **`TARGET MET`** (`controllerCount -eq 0`): The customisation budget held. The demo is built entirely on stock DW10 + configuration. This is the win condition, and the slide reads as a clean "zero customisations" pitch beat.

- **`TARGET MISSED`**: One or more custom controllers exist under `Dynamicweb.Host.Suite/Controllers/`. Cross-reference each `Controllers\*Controller.cs` against the ledger row by row. If a row is missing for a file, that file was written **without preflight** (a bypass of the customisations-ledger preflight) -- investigate before declaring the phase complete. If a row exists but the file is also there, the customisation was approved at write-time and is a deliberate trade-off; the slide narrative becomes "N approved customisations, all listed in the ledger" rather than "zero."

- **`controllerCount -eq ledgerCount` (both > 0)**: Customisation budget held to plan. Each customisation has a logged reason. Acceptable for the pitch, but the win condition is still zero.

## 5. Detection signature for a preflight bypass

If `controllerCount > ledgerCount`, at least one file was written without going through the customisations-ledger preflight. Walk the difference:

```powershell
$loggedFiles = (Get-Content "CUSTOMISATIONS.md" -ErrorAction SilentlyContinue) |
  Where-Object { $_ -match '^\|\s*\d{4}-\d{2}-\d{2}' } |
  ForEach-Object {
    # Column 2 of the row, trimmed
    ($_ -split '\|')[2].Trim()
  }

$onDiskFiles = Get-ChildItem -Recurse "Dynamicweb.Host.Suite/Controllers" -Filter "*Controller.cs" -ErrorAction SilentlyContinue |
  ForEach-Object { $_.FullName -replace [regex]::Escape((Get-Location).Path + '\'), '' -replace '\\', '/' }

$missingFromLedger = $onDiskFiles | Where-Object { $loggedFiles -notcontains $_ }
if ($missingFromLedger) {
  Write-Host "Files on disk without ledger rows (preflight bypass):"
  $missingFromLedger | ForEach-Object { Write-Host "  $_" }
}
```

This is a defense-in-depth check: the convention-based preflight assumes Claude reads `SKILL.md` and follows the rule. If a future model bypasses the preflight, this audit catches the residue post-hoc. The audit recipe IS the verifier for the closing customisation-budget success criterion.
