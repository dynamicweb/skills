# Customisations governance

Customisations governance for the per-demo project. Two artefacts: the per-demo `<demo>\CUSTOMISATIONS.md` ledger (template at `assets/CUSTOMISATIONS.md.template`, dropped at scaffold time) AND the write-time preflight that appends to it. The audit recipe (`references/audit-customisations.md`) is the verifier -- its output is paste-ready slide content for the demo's closing customisation-budget review.

This file is the long-form contract for **the customisations-ledger preflight**. The orchestrator's summary -- including the canonical preflight prompt -- lives in `SKILL.md` "Two guarded-writes"; see also the sister contract `references/customer-context.md` (the customer-context read-only contract) which shares the *same mental model* -- write-time preflight on a path glob -- with a single hard-abort branch instead of three.

## What the rule *actually* forbids vs. doesn't forbid

The rule forbids backend C# code under specific globs:
- `Dynamicweb.Host.Suite/Controllers/**/*.cs`
- `Dynamicweb.Host.Suite/Providers/**` (PriceProvider, PaymentProvider, etc.)
- Any `*Controller.cs`

These DO NOT count as customisations and SHIP unprompted:

| Surface | Ledger row? | Reason |
|---------|-------------|--------|
| `NotificationSubscriber` subclass | NO | Standard cross-cutting hook; in `Dynamicweb.Examples` |
| Static helper class | NO | Not in preflight glob |
| Custom item type definition (`<Prefix>_*.xml`) | NO | Content schema, not code |
| Razor template edit | NO | `.cshtml` outside preflight glob per re-skin.md Â§5 |
| Custom field on `AccessUser` / `EcomProducts` / `ProductGroup` | NO | Data change |
| Custom SQL helper / repository class (read-only) | NO | Not in preflight glob â€” but consider an MCP gap instead |

**Why this matters:** projects routinely over-interpret the rule to bar Notification subscribers, which then forces SQL backfills (`OrderCustomerNumber`, `OrderComplete=1`) that should have been runtime subscribers. The rule is conservative-by-design â€” the pitch beat of "low customisation budget" depends on it â€” but conservatism applies to Controllers/Providers, not "any code we write."

Cross-reference: [`../../dw-demo-swift/references/dw10-canonical-surfaces.md`](../../dw-demo-swift/references/dw10-canonical-surfaces.md) Â§"Cross-cutting redirects" â€” the `NotificationSubscriber` on `Notifications.Standard.Page.Loaded` is the canonical anon-gate / role-gate hook and does NOT trigger this preflight.

## 1. Ledger template location

The per-demo ledger lives at `<demo>\CUSTOMISATIONS.md` (solution root, **NOT** under `Dynamicweb.Host.Suite\`). The template at `assets/CUSTOMISATIONS.md.template` is dropped at scaffold time (see `references/scaffold.md` Section 6 -- at scaffold time, copy `assets/CUSTOMISATIONS.md.template` to `<demo>\CUSTOMISATIONS.md`, replacing `<demo-name>` with the actual demo folder name).

The ledger is **append-only by convention.** The audit recipe reads it; the write-time preflight appends to it on the Approve+log branch. Nothing else writes to it.

## 2. Drop the template at scaffold time

This snippet executes during a fresh scaffold flow. It is idempotent in the sense that running it twice overwrites the existing ledger -- which is fine on first scaffold and not what you want afterwards. Skip this block if `CUSTOMISATIONS.md` already exists in the working directory:

```powershell
$skill = "$HOME\.claude\skills\dynamicweb-demo-base"
$demoName = Split-Path -Leaf (Get-Location)
$template = Get-Content "$skill\assets\CUSTOMISATIONS.md.template" -Raw
$ledger = $template -replace '<demo-name>', $demoName
Set-Content -Path "CUSTOMISATIONS.md" -Value $ledger -Encoding UTF8
Write-Host "Dropped CUSTOMISATIONS.md ledger for demo: $demoName"
```

For an idempotent variant that refuses to overwrite an existing ledger:

```powershell
if (Test-Path "CUSTOMISATIONS.md") {
  Write-Host "CUSTOMISATIONS.md already exists -- leaving it alone."
} else {
  $skill = "$HOME\.claude\skills\dynamicweb-demo-base"
  $demoName = Split-Path -Leaf (Get-Location)
  $template = Get-Content "$skill\assets\CUSTOMISATIONS.md.template" -Raw
  $ledger = $template -replace '<demo-name>', $demoName
  Set-Content -Path "CUSTOMISATIONS.md" -Value $ledger -Encoding UTF8
  Write-Host "Dropped CUSTOMISATIONS.md ledger for demo: $demoName"
}
```

## 3. Write-time preflight (mandatory)

Before writing any file matching the globs in Section 5, **INVOKE `AskUserQuestion`** -- the canonical prompt (exact wording + the three branch outcomes Approve+log / Refactor instead / Cancel) lives in `SKILL.md` "Two guarded-writes". Do not paraphrase it from here.

**Rationale:** Many B2B customers are fleeing heavily-customised legacy commerce/ERP stacks. The customisation budget is itself a pitch beat at the demo's closing slide -- every approved row is a deliberate trade-off; every Cancel/Refactor is a small win. (The exact slide checkpoint is project-specific; see the demo's `.planning/` for the budget review milestone.)

## 4. Approve+log row format

On Approve+log, append exactly this row format to `<demo>\CUSTOMISATIONS.md`:

```
| YYYY-MM-DD | <relative path from solution root> | controller / provider / razor / other | <one-sentence reason from the user> | <approver name> |
```

Example:

```
| 2026-08-15 | Dynamicweb.Host.Suite/Controllers/PunchOutController.cs | controller | Inbound cXML endpoint for DEMO-40 punch-out simulator. Stock providers don't expose a cXML body parser. | Justin |
```

The audit recipe (`references/audit-customisations.md`) reads these rows by matching `^\|\s*\d{4}-\d{2}-\d{2}` -- the date-prefix is the row marker. Rows without an ISO-8601 date in column 1 are ignored by the audit (intentional -- header rows, separator rows, and the placeholder `_(append rows here)_` row are excluded).

## 5. Glob coverage notes

The preflight globs are intentional:

- `Dynamicweb.Host.Suite/Controllers/**/*.cs` -- primary target. The end-of-build audit verifies this folder contains zero `.cs` files.
- `Providers/**` -- any custom Provider class anywhere in the solution. Providers (notification, payment, shipping, integration, etc.) are a customisation-budget category in their own right.
- `*Controller.cs` -- broader catch-all. Matches `Controllers/Foo.cs`, `Areas/Admin/BarController.cs`, anywhere in the tree, even if not under a folder named `Controllers/`.

Razor files (`*.cshtml`) are **NOT** in the preflight glob. DW10 templates are conventional, not "customisations" in the pitch sense -- a Swift template override is part of normal demo-build flow, not a customisation-budget hit. If a razor IS modified for a clearly-customisation reason (e.g., hard-coded business logic in a template), it goes in `CUSTOMISATIONS.md` as a `razor` type row by user request, not by preflight. The Razor escalation ladder for Swift demos lives in `dynamicweb-swift-demo/references/re-skin.md` Â§Pixel-perfect escalation.

## 6. Cross-references

- The audit recipe lives at `references/audit-customisations.md` -- run it on demand and at end of every phase.
- The customer-context guard (`references/customer-context.md`) shares the *mental model* (write-time preflight) but uses a hard-abort branch only.
- SKILL.md's "Two guarded-writes" section is the orchestrator's summary and owns the canonical preflight prompt; this file is the long-form contract.
- `assets/CUSTOMISATIONS.md.template` is the parametric ledger (single placeholder: `<demo-name>`).


