# admin-ui-authoring.md

> Swift 2 admin-UI authoring: the configuration-only Day-1 workflow (get 80% of the brand applied via admin Style tools alone, zero CSS / Razor / .cs edits) plus the Visual Editor patterns for editing paragraph properties without touching code. Operates against a deserialized swift/2.3 `base` layer (source-of-truth at `<demo-root>\distribution\layers\base\`).
>
> Swift 2.x guidance — never follow `/swift/swift-1/` URLs (different content model, phased out).

## The workflow + Visual Editor surface map live in the foundational skill

Vendor-generic Swift configuration-only authoring — the 5-step Day-1 workflow (mood board → translate into admin Style tools → upload assets → connect styles via Website Settings → build layout in the Visual Editor), the Visual Editor surface map, and the "what the VE covers, and the escalation per gap" table — is owned by the `dw-swift-building` foundational skill — staged in [`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §9 ("Re-skin doctrine"). Read that section for the click-paths and the per-gap escalation.

This file carries the demo-specific framing: where the mood board comes from, the executor split, and the escape hatches that are out of scope.

## When to use + executor split

The configuration-only approach is the default starting point for any Swift 2 demo re-skin — it covers most copy / asset / layout work with zero code. **Mood board source:** pull from the demo's read-only `<demo>\customer-context\` (intro-call materials, brand guide, the customer's public site as reference) — never invent.

**Executor split:** the admin click-paths in the foundational §9 surface map are the *map* of what is configurable — for a human doing manual authoring, and as verification targets. When Claude makes a change itself, it resolves the click-path to the equivalent MCP / Management API call (every Visual Editor / Style-tools save is an Admin API call underneath) per the base surface-priority rule — [dynamicweb-demo-base/references/surface-priority.md](../../dw-demo-base/references/surface-priority.md) §"Admin UI is verification-only during the build". Claude drives `/Admin` via Playwright only to verify a change landed, never to author.

Escalate to [re-skin.md](re-skin.md) §`<customer>_custom.css` only when the admin Style tools cannot express the visual you need; escalate further (content-layout `.cshtml`) only when a tailored screen requires a new rendering — see [re-skin.md](re-skin.md) §Pixel-perfect escalation. Only the controller/provider `.cs` tier triggers base's customisations-ledger preflight ([dynamicweb-demo-base/references/customisations.md](../../dw-demo-base/references/customisations.md)).

## Management API authoring traps (Swift 2.4 / DW 10.28.x)

Because every Visual-Editor / Style-tools save resolves to an Admin API call, Claude writes through
those calls directly — and several of them report success in ways that are not true. Standing rule:
**after any write, re-read the entity AND fetch the rendered page. `status=ok` and the POST response
model are not evidence.**

**`GridRowSave` — the response model lies.** It *does* accept and persist `colorSchemeId` (stock
Swift vocabulary: `light|lightgrey1|lightgrey2|dark|darksubtle|primary|secondary`), but the POST
response `.model` returns a stale/empty `colorSchemeId` and a blank `successful` flag even on a
successful write. Only a fresh `GET /Admin/Api/GridRowById?Id=<id>` reflects the committed value —
poll it until it equals the target before the next save (serialise + verify), and confirm the live
section wrapper carries `data-dw-colorscheme="<id>"`. Strip `modelIdentifier` from the model before
posting. Section colour-scheme rhythm needs no admin-UI capture/replay; the API is fully sufficient.
Related shape: `GET /Admin/Api/GridRowsByPageId?PageId=<id>` is paginated — the rows live under
`model.data` (already in render/sort order), not `model[]`.

**`flexibleColumns` is inverted: `0` = flexible, `1` = fit-to-content.** In the `GridRowSave`
`flexibleColumns` array the column listed `0` silently absorbs all remaining horizontal space
(computes `flex: 1 1 auto`, `class="flex-fill"`); entries of `1` compute `flex: 0 1 auto` and size
to content. `[0,1,1,1,1,1]` reads as "column 1 is not flexible" and does the opposite — a logo
column swallowing ~960px for a 264px logo is the usual symptom. To make column N flexible, set index
N-1 to `0` and every other entry to `1`, then assert the intended column carries Bootstrap's
`flex-fill` and the others compute content-sized widths.

**`PageSave` re-derives the page `name` from the item `Title`.** When `name` is not supplied in the
same call, DW overwrites the page name from the item `Title` field and then regenerates
`friendlyUrl` from the new name — 404-ing the old URL. This bites hardest on duplicated pages, whose
item `Title` still carries the source page's title while the page `name` was renamed by hand: a save
that touched an unrelated flag renames the page and breaks a URL the demo's gate asserts.
**Never `PageSave` a page without setting `name` AND `Title` in the same call**, and keep the item
`Title` aligned with the page name afterwards or the next save renames it again. Verification: after
any `PageSave`, re-fetch (a) the saved page's own `friendlyUrl` and (b) every URL in the demo's gate
page list, asserting 200 or 301 — a rename shows up **only** as a 404 on the OLD url, which a
`status=ok` check and a page-object diff both miss. Also assert `name` still equals what you
submitted.

**`showInLegend` is not a navigation filter.** It round-trips `false` through `PageSave` and has
ZERO effect on rendered navigation — the navigation providers do not consult it. To suppress a
duplicated nav/footer link, hide it in CSS or remove the page from the menu source; do not spend a
`PageSave` (with the rename risk above) on this flag.

**`PageCopy` inherits more than you want, and the copy can win the render.**

- Copies carry the source page's paragraph `Button` fields verbatim, with no reset offered. One
  source CTA reappears once per copied paragraph — e.g. a single "Discover more" `FirstButton`
  duplicated across every copied row, on top of each row's own correct inline link. Blank or repoint
  `FirstButton` on every copied paragraph afterwards (as an object with blank members — see
  [paragraphs.md](paragraphs.md) §ButtonData), and assert the source label's rendered count is 0.
- A copy made as a header shortcut (`shortCut=/Default.aspx?ID=<target>`, `publicationState=
  published`) can be the page that actually renders the storefront chrome, while the page carrying
  the `navigationTag` (e.g. `ProductListPage`) sits `hideInMenu` and inert. Editing the tagged page
  then changes nothing while every API read-back reports success — a teaser authored there is
  invisible. **Resolve chrome pages by RENDERED PARAGRAPH ID, never by nav tag**: grep the delivered
  HTML for the paragraph ids you expect (breadcrumb / product-list info / component selector / list
  navigation) before and after the edit, assert the ids of the page you did NOT edit stay absent,
  and re-run the count on more than one list URL.

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
