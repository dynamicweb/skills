# admin-ui-authoring.md

> Swift 2 admin-UI authoring: the configuration-only Day-1 workflow (get 80% of the brand applied via admin Style tools alone, zero CSS / Razor / .cs edits) plus the Visual Editor patterns for editing paragraph properties without touching code. Operates against a deserialized swift/2.3 baseline (source-of-truth at `<demo-root>\baselines\swift-2.3\`).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## The workflow + Visual Editor surface map live in the foundational skill

Vendor-generic Swift configuration-only authoring — the 5-step Day-1 workflow (mood board → translate into admin Style tools → upload assets → connect styles via Website Settings → build layout in the Visual Editor), the Visual Editor surface map, and the "what the VE covers, and the escalation per gap" table — is owned by the `dw-swift-building` foundational skill — staged in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9 ("Re-skin doctrine"). Read that section for the click-paths and the per-gap escalation.

This file carries the demo-specific framing: where the mood board comes from, the executor split, and the escape hatches that are out of scope.

## When to use + executor split

The configuration-only approach is the default starting point for any Swift 2 demo re-skin — it covers most copy / asset / layout work with zero code. **Mood board source:** pull from the demo's read-only `<demo>\customer-context\` (intro-call materials, brand guide, the customer's public site as reference) — never invent.

**Executor split:** the admin click-paths in the foundational §9 surface map are the *map* of what is configurable — for a human doing manual authoring, and as verification targets. When Claude makes a change itself, it resolves the click-path to the equivalent MCP / Management API call (every Visual Editor / Style-tools save is an Admin API call underneath) per the base surface-priority rule — [dynamicweb-demo-base/references/surface-priority.md](../../dw-demo-base/references/surface-priority.md) §"Admin UI is verification-only during the build". Claude drives `/Admin` via Playwright only to verify a change landed, never to author.

Escalate to [re-skin.md](re-skin.md) §`<customer>_custom.css` only when the admin Style tools cannot express the visual you need; escalate further (content-layout `.cshtml`) only when a tailored screen requires a new rendering — see [re-skin.md](re-skin.md) §Pixel-perfect escalation. Only the controller/provider `.cs` tier triggers base's customisations-ledger preflight ([dynamicweb-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md)).

## Verification: did the change land via the admin UI?

After any Visual Editor / Style-tools edit on a running host, `git status` should show ONLY:
- `Dynamicweb.Host.Suite/wwwroot/Files/Images/<your-uploaded-asset>` (logo / hero swaps)
- `Dynamicweb.Host.Suite/wwwroot/Files/Templates/Designs/Swift-v2/<paragraph-instance-config>.json` (paragraph property persistence — config, not Razor)
- `Files/System/Styles/{ColorSchemes,Buttons,Typography}/*.{json,css}` (Style-tools saves — see [styles-assets.md](styles-assets.md))

You should NEVER see `*.cs` changes in `Controllers/` or `Providers/` (triggers base's customisations-ledger preflight), `*.scss` / `*.ts` changes (recompilation drift), or changes to any file named exactly `custom.css` (Swift-shipped sample code — brand CSS belongs in `<customer>_custom.css`; the hard rule lives in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9). New content-layout `.cshtml` files are part of the normal escalation ladder ([re-skin.md](re-skin.md) §Pixel-perfect escalation); *modifications* to existing standard `.cshtml` are the thing to avoid.

## What this surface does NOT do (escape hatches)

Some changes don't have an admin-UI authoring surface and require either preflight-approved customisation or live in a different skill:

- **Customer-center CSR section customisation** — never; see [customer-center.md](customer-center.md) (the stock-CSR rule).
- **Customer-flavoured products / orders seeding** — project-specific data work, not a styling concern.
- **New product fields / completeness rules** — PIM concern. See [dynamicweb-pim-demo/references/structural-model.md §2.8](../../dw-demo-pim/references/structural-model.md) and `dynamicweb-pim-demo/references/canonical-setup-order.md` step 7.
- **MCP tool wiring** — base concern. See `dynamicweb-demo-base/references/mcp-setup.md`.
- **Custom payment provider / shipping carrier** — out of scope for Dynamicweb demos (a known customisation trap).
- **`<customer>_custom.css` / `.scss` / `.cshtml` work** — the escalation ladder in [re-skin.md](re-skin.md). (Brand CSS never goes in a file named `custom.css` — that's Swift-shipped sample code; hard rule in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9.)
