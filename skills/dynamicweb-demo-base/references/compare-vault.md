# Compare Vault — drift detection across machines

Vault drift detection. Skill-only recipe — fenced PowerShell that hashes slot contents and emits a slot-by-slot drift summary (no standalone `.ps1` script).

The vault at `$env:DW_VAULT` is meant to be **identical across all dev machines** (Justin's box, demo-machine, future contributors). If two machines diverge, every sister skill that reads vault content will produce subtly different results — the demo that "works on Justin's machine" suddenly doesn't. This recipe is the diagnostic.

---

## When to run

- **"This works on Justin's machine but not mine."** — drift is the most likely cause; this recipe is the first triage step.
- **Before installing a new demo on a fresh box.** — verify the freshly-copied vault matches the source machine.
- **When a baseline rolls.** — Swift 2.2 → Swift 2.3, DW10 source bump, new sample bundles. The "Last-updated" column in `INDEX.md` should be bumped on the authoritative machine; the recipe confirms downstream machines are in sync.
- **As a sanity check before declaring base setup complete on a new machine.**

---

## What it does

Walks each slot in `INDEX.md`, hashes the contents, emits a Markdown summary. Compare two outputs (one per machine) to find drift. Per-slot SHA-256 manifest hash + file count per slot.

---

## Recipe

```powershell
$vault = $env:DW_VAULT
if (-not $vault) { throw "DW_VAULT not set. Run setup-checks.md first." }
$slots = "dw10source","samples","databases","docs","serialized-data"

$report = foreach ($slot in $slots) {
  $path = Join-Path $vault $slot
  if (-not (Test-Path $path)) {
    [pscustomobject]@{ Slot = $slot; FileCount = 0; ManifestHash = "(missing)" }
    continue
  }
  $files = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName
  $count = ($files | Measure-Object).Count
  # Concatenate per-file hashes (order-stable via Sort-Object FullName), then hash the concatenation.
  $combined = ($files | Get-FileHash -Algorithm SHA256 | ForEach-Object { $_.Hash }) -join ""
  $manifestHash = if ($combined) {
    [BitConverter]::ToString(
      [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($combined)
      )
    ).Replace("-","")
  } else { "(empty)" }
  [pscustomobject]@{ Slot = $slot; FileCount = $count; ManifestHash = $manifestHash }
}

$report | Format-Table -AutoSize
```

The recipe sorts files by `FullName` before hashing so the resulting `ManifestHash` is order-stable across runs and across machines (different filesystems can return different default enumeration orders). Without `Sort-Object`, two identical vault copies could produce different manifest hashes — that's a false-positive drift signal.

### Example output

```
Slot              FileCount ManifestHash
----              --------- ------------
dw10source             2843 9F3C8A2E1D7B5...
samples                 412 7E1D9A8B4F2C6...
databases                 2 (B2C-database.zip + purge-cleandb.sql hashes)...
docs                     38 4A8B7C2D1E9F5...
serialized-data         156 6F5E4D3C2B1A9...
```

---

## Drift verdict

Two machines should produce **identical `ManifestHash` per slot**. Mismatch policy:

| Slot mismatch | Diagnosis |
|---|---|
| `dw10source` differs | Source-tree drift. The two machines have different DW10 source-clone snapshots. Update the lagging machine via `git pull` (or `git reset --hard <ref>` if the trail diverged). |
| `samples` differs | Sample bundle drift. Usually means `dw10adminUI/` was updated on one box and not the other. |
| `databases` differs | DB snapshot drift. The `swift2.2.0-<date>-database.zip` or similar artefact was rolled. Check INDEX.md `Last-updated`. |
| `docs` differs | Curated docs drift. Usually intentional — one machine added a new doc — and resolved by copy. |
| `serialized-data` differs | **Highest-stakes drift.** Baseline rolls cascade into Swift's [`../../truvio-swift-demo/references/deserialize-flow.md`](../../truvio-swift-demo/references/deserialize-flow.md) results. Check INDEX.md and the per-baseline subfolder's own `README.md` for the version stamp. |

**Resolution:** the authoritative machine bumps `INDEX.md`'s `Last-updated` column for the affected slot, then mirrors the slot to the other machine (typically via robocopy / sync tool / archive download). Run the recipe again on both boxes; manifest hashes should now match.

If a baseline-roll is the cause, escalate to the team — multiple machines need updates, and downstream sister skills' assumptions may need revisiting.

---

## Cross-reference: baseline-drift self-diagnosis

If grep results in any sibling skill (PIM, Swift) contradict the live vault — say a `truvio-pim-demo` reference says "expect 17 product groups in the Swift baseline" but the live deserialize produces 19 — this recipe's output is the diagnostic. Was the `serialized-data\Swift2.2\` slot rolled? Cross-check `INDEX.md`'s `Last-updated` and version-stamp columns. Reality wins; the skill is the second source of truth.
