# DW10 canonical surfaces — use these, don't re-implement

> The "use X, not Y" cheat sheet for the DW10 surfaces that get re-implemented in Razor. When in doubt, search `dw10source` (vault: `$env:DW_VAULT/dw10source`) for the canonical surface before writing SQL or parsing URLs. Non-optional on every demo build. Also home to the custom item-type discipline and the discipline-audit grep pack (sections below).
>
> **Why this exists.** Every "fake pattern" in a Swift demo (raw SQL probes on `AccessUserGroupRelation`, hard-coded area prefixes, master-template `WriteLiteral` redirects, `EcomOrders` SQL chains in Razor) is a workaround for a surface the demo author didn't know was there. This file is the inventory. Cross-references the escalation ladder in [`re-skin.md`](re-skin.md) §Pre-escalation check — search here first.

## User identity / groups

- **Read user**: `Pageview.User` (the model; not a viewmodel). Public properties include `ID`, `Name`, `FirstName`, `LastName`, `UserName`, `Email`, `CustomerNumber`, `PointBalance`.
- **Read user groups**: `Pageview.User.GetGroups()` returns `IEnumerable<UserGroup>`. Non-obsolete on 10.25+ — see `src/Core/Dynamicweb.Core/Security/UserManagement/User.cs:717`. `User.HasGroup(int)` (User.cs:1329) is `[Obsolete]` but compiles.
- **From viewmodel side**: `UserViewModelExtensions.GetDirectUserGroups()` (`Frontend/UserViewModelExtensions.cs:54`).
- **NEVER**: raw `SELECT FROM AccessUserGroupRelation` in Razor.

## Permissions — the entity store

The single load-bearing fact that prevents the entire "SQL-write to `EcomParagraph.ParagraphPermission`, then template-shim because nothing gates" detour: DW10's `Page` and `Paragraph` permissions are stored in the **`Permission` table**, not in the legacy `Page.PagePermission` / `EcomParagraph.ParagraphPermission` columns. The legacy columns exist for back-compat but the runtime renderer reads from `Permission`.

### Schema

```
Permission
  PermissionOwnerName    ('Page' | 'Paragraph' | ...)
  PermissionOwnerKey     (entity id, e.g. '24' for paragraph 24)
  PermissionAccessUserGroupId  OR  PermissionAccessUserId
  PermissionLevel        (1=Read, 2=Edit, 4=Delete, etc.)
  PermissionExplicitDeny (0=allow, 1=deny)
```

### Enforcement points in dw10source

- Page navigation tree filter: `PageNavigationTreeNodeProvider.cs:161` — `page.HasPermission(PermissionLevel.Read)`.
- Page-level redirect for anon: `PageView.cs:399-427` `CheckPermissionsAndRedirect()` auto-302s anon hits to the area's login module page.
- Paragraph render: `Frontend/Content.cs:398` — returns `ContentOutputResult.Empty` when `paragraph.HasPermission(PermissionLevel.Read)` fails.

### How to gate a page subtree (e.g. CSR section)

1. Set `Page.PermissionType = 0` on the root + descendants.
2. INSERT into `Permission` one row per (page, group) binding read-access.
3. No template edits needed. Nav, redirect, and child-render all self-filter.

### How to hide a single paragraph from non-CSR users

1. INSERT into `Permission`: `('Paragraph', '<paragraphId>', <csrGroupId>, 1, 0)`.
2. The frontend renderer's `Content.cs:398` returns empty content for users without that read row.

### Common misdiagnosis

If your `Page.PagePermission` or `EcomParagraph.ParagraphPermission` UPDATE didn't gate the entity from frontend users, you wrote to the **wrong table**. The legacy column is admin-side only. The runtime check uses the `Permission` table.

Symptoms of writing to the wrong column:
- Paragraph still renders for anon users despite `ParagraphPermission='9'`.
- Page still navigable from the menu despite `PagePermission='<groupId>'`.
- Admin Permissions panel shows the legacy column value but the storefront ignores it.

Fix: revert the legacy-column write, INSERT the equivalent row into `Permission`, and remove any template shims that were added to compensate for the non-gate.

### MCP coverage

`mcp__dynamicweb-pim__assign_permissions_to_assortment` writes assortment permissions; there is no equivalent generic MCP for page/paragraph yet. SQL or admin UI for now. Flag MCP enhancement: `set_entity_permission(entityType, entityKey, groupId, level)`.

### Never

- **NEVER**: SQL-write the legacy column and assume the renderer reads it. SQL-write to `Permission` (with the right owner name + key + group + level), OR set permissions in the admin Permissions panel.

## Pricing

- **Read tier prices**: `Services.Prices.GetByProductId(productId)` — currency / customer-group / shop scoped by the configured `IPriceProvider`. dw10source `Prices/Price.cs:179`.
- **Custom price logic**: `PriceProvider` subclass. dw10source `Prices/PriceProvider.cs:17`. Override `FindPrice(PriceContext, PriceProductSelection)` for line price, `FindQuantityPrices` for qty-break tier rows, `PreparePrices` for batched ERP fetch.
- **NEVER**: raw `SELECT FROM EcomPrices` in Razor. The query returns rows from all customer-group scopes, leaking pricing.

## Orders

- **Read customer orders**: `Services.Orders.GetCustomerOrdersByType(int customerId, string shopIds, OrderType, int recurringOrderId, string customerNumber, string orderContextIds, DateTime fromDate, bool includeImpersonation, bool isCart, bool includeUserAndSecondaryUserIds)`. dw10source `Orders/OrderRepository.cs:1905`.
- **Search**: `Services.Orders.GetOrdersBySearch(OrderSearchFilter filter)`. `OrderRepository.cs:1196`.
- **Both return `Order` aggregates** with `.OrderLines` materialised.
- **NEVER**: hand-roll a 4-subquery `EcomOrders/EcomOrderLines` SQL chain in Razor.

## Products

- **Get product**: `Services.Products.GetProductById(productId, variantId, true)` (the `true` = include all fields, materialise `ProductFieldValues`).
- **Get product URL**: `Services.Products.GetProductUrl(...)` or `SearchEngineFriendlyURLs.GetFriendlyUrl(...)`.
- **Get product groups**: `Services.ProductGroups.GetGroup(id).Subgroups`.
- **NEVER**: parse a URL or `Request.RawUrl` to identify a product.

## URLs

- **Friendly URL for a page**: `SearchEngineFriendlyURLs.GetFriendlyUrl(pageId)`.
- **Page ID by tag**: `GetPageIdByNavigationTag("tag")` (helper available in Swift templates).
- **Canonical share URL**: `Pageview.Meta.Canonical?.ToString()` (NOT `Request.Url.AbsoluteUri` — that captures tracking params + proxy hostnames).
- **NEVER**: hard-code area prefixes (`/<brand-slug>/...`) or synthesize `/Default.aspx?ID=...` strings.

## Stylesheets / scripts

- **Page-scoped css/js**: `AddStylesheet(...)` / `AddScript(...)` in the same `@{}` block as the paragraph setup code. Swift master hoists, dedups, orders.
- **Project-scoped includes**: `Area.Item.CustomHeadInclude` field pointing at `Custom\<Customer>HeadInclude.cshtml`. The stock master already renders this partial if set. Stock example: `Custom\CustomHeadIncludeExample.cshtml`. See also [`re-skin.md`](re-skin.md) §"Wiring up project-scoped custom.css".
- **NEVER**: inline `<script src="...">` in a paragraph template (re-emits per paragraph appearance, breaks cache-busting). **NEVER**: inline `AddStylesheet(...)` in `Swift-v2_Master.cshtml`.

## Cross-cutting redirects (anon gate, role gate, etc.)

- **Canonical hook**: a `NotificationSubscriber` on `Notifications.Standard.Page.Loaded` that sets `loadedArgs.OutputResult = new RedirectOutputResult { RedirectUrl = ... }`. Fires before any Razor streams. dw10source `PageView.cs:388-392`. **A subscriber is NOT a hit on the customisations-ledger preflight** — see [`../../dynamicweb-demo-base/references/customisations.md`](../../dynamicweb-demo-base/references/customisations.md) §"What the rule *actually* forbids vs. doesn't forbid".
- **For "anon hits a permission-required page"**: don't write anything. Configure `Page.PermissionType = 0` + a `Permission` row, and `CheckPermissionsAndRedirect()` takes care of it.
- **NEVER**: `WriteLiteral` + `return;` from inside `Swift-v2_Master.cshtml`. That's a workaround for using the wrong layer.

## Per-category behavior

- **Storage**: `ProductGroup.ProductGroupFieldValues` (group-level custom fields).
- **Read**: `product.PrimaryOrDefaultGroup.ProductGroupFieldValues["FieldName"]`.
- **NEVER**: `product.PrimaryOrDefaultGroup.Name.Contains("roof")` in Razor. Marketing renames the group → silent breakage.

## Product field arrays / lists

- **Define**: a `ProductField` of type `ListBox` / `EditableList` / repeater.
- **NEVER**: regex on `LongDescription` to lift `<li>` items.

## Custom item types — the `<Prefix>_*` discipline

When a paragraph block needs editor-configurable fields that aren't on Swift's stock item types, create a **new item type** with a project prefix (`Acme_PointsDashboard`, `Acme_RebateTracker`) — not "another Swift-v2_Text variant". This explicitly forbids the "Swift-v2_Text shim + foreign cshtml" pattern.

### What this looks like in practice

1. Define `Files\System\Items\<Prefix>\<Prefix>_<ConceptName>.xml`. Schema = same shape as stock `Swift-v2_*.xml` files; copy `Swift-v2_Text.xml` as a starting template.
2. Place layout at `Templates\Designs\Swift-v2\Paragraph\<Prefix>\<Prefix>_<ConceptName>\<Prefix>_<ConceptName>.cshtml`.
3. Restart host so `ItemTypeProvider` discovers it.
4. New "Add paragraph" picker entry in Visual Editor under your project's category.

### Repeater fields

When a block has N repeating children (tiers, rules, list items), create both:
- `<Prefix>_<Concept>.xml` (the parent) with an `ItemRelationListEditor` field
- `<Prefix>_<Concept>_<Child>.xml` (the sub-item)

Reference: stock `Swift-v2_Accordion.xml` + `Swift-v2_Accordion_Item.xml`.

### What to put where

Three rules for what stays in cshtml vs moves to a field:

1. **Editor copy** (labels, microcopy, hero copy, fineprint, CTA labels) → ALWAYS a field. Even one-off strings. Editors will want to change them.
2. **Data-shape transformations / math / lookups** → cshtml. Computing dial degrees, formatting currency, deriving "is unlocked" booleans → cshtml.
3. **Magic numbers** (threshold = 10000, windowDays = 90, maxChips = 8) → fields with sensible defaults. The default lives in the XML; the editor can override.

### Things to NEVER do

- ❌ **Repurpose a generic item type** (`Swift-v2_Text`) and attach a foreign cshtml. The editor sees `Title/Subtitle/Text/FirstButton/SecondButton`; the template ignores most of them and embeds the real fields as hardcoded strings.
- ❌ **One cshtml per "variant"** with hardcoded forks. Use a field with a multi-select / radio for the variant.
- ❌ **Bake category-aware copy into cshtml** with `.Contains("roof")` chains. Put the category-aware copy on a `ProductGroup` field instead — see §"Per-category behavior" above.

### Audit query

When a project's customisation budget is being audited, list all paragraph templates that don't match `Swift-v2_*` and aren't in a project-prefixed folder:

```powershell
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2\Paragraph\Swift-v2_*\*" -Filter '*.cshtml' `
    | Where-Object { $_.Name -notlike 'Swift-v2_*' }
```

Anything that surfaces here is a "Swift-v2_Text shim" smell. Refactor to a custom item type. See also §"Discipline audit — grep pack" grep #6 below.

### Reference example

A worked example with the full repeater pattern: `<Brand>_PointsDashboard.xml` + `<Brand>_PointsDashboard_Tier.xml` (Item type + repeater child + content layout cshtml + `<customer>_custom.css` block). Copy from a current demo where the pattern has landed.

## Discipline audit — grep pack

Verify a Swift demo's templates against this file's canonical surfaces before declaring "ready" or before plugin fold-back. Each hit is a candidate finding; a clean run = green light. Sister audit: [`../../dynamicweb-demo-base/references/audit-customisations.md`](../../dynamicweb-demo-base/references/audit-customisations.md) is the recipe for the customisations-ledger preflight; this pack is its peer for the discipline checks that don't show up in `git status` of `.cs` files.

### When to run

- Before declaring a demo "ready" (end-of-build budget review).
- Before folding learnings back into the plugin (so the plugin's reference docs aren't carrying lessons the active demos haven't applied).
- After any escalation up [`re-skin.md`](re-skin.md) Tier 3+ — a `.cshtml` write is the most likely place to acquire one of these anti-patterns.

### Prerequisites

```powershell
$Root = "Dynamicweb.Host.Suite\wwwroot"  # adjust if running outside the demo's solution root
$Slug = "<area-url-slug>"                 # e.g. "<brand-slug>" — a demo's hardcoded area prefix you want to scan for
```

### The grep pack

```powershell
# 1. Raw DB access in Razor (should be zero — use Services.* APIs per the surface inventory above)
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' `
  | Select-String -Pattern 'Database\.(CreateDataReader|ExecuteScalar|ExecuteReader|ExecuteNonQuery)'

# 2. Substring scans on URL/query (should be zero — use page-id helpers + Pageview.User per the surface inventory)
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' `
  | Select-String -Pattern 'PathAndQuery\.IndexOf|QueryString\.ToString|Url\.AbsoluteUri\.Contains'

# 3. Hard-coded area prefixes (set $Slug per project)
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' `
  | Select-String -Pattern "/$Slug/"

# 4. Default.aspx?ID= synthesized links (should be zero outside legacy compat)
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' `
  | Select-String -Pattern 'Default\.aspx\?(ID|GroupID|ProductID)='

# 5. Category-name substring branching (should be zero — use ProductGroup field per §"Per-category behavior")
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' `
  | Select-String -Pattern '\.PrimaryOrDefaultGroup.*\.(Name|Title).*\.(Contains|StartsWith)'

# 6. Swift-v2_Text shim smell (project files under generic item folders — see §"Custom item types")
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2\Paragraph\Swift-v2_*\" -Recurse -Filter '*.cshtml' `
  | Where-Object { $_.Name -notlike 'Swift-v2_*' }

# 7. Inline AddStylesheet / AddScript in master (should be zero — use Area.Item.CustomHeadInclude per re-skin.md)
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2\Swift-v2_Master.cshtml" `
  | Select-String -Pattern 'AddStylesheet|AddScript'

# 8. Regex on LongDescription / ProductName (should be zero — use ProductField list types per §"Product field arrays / lists")
Get-ChildItem -Path "$Root\Templates\Designs\Swift-v2" -Recurse -Filter '*.cshtml' `
  | Select-String -Pattern 'Regex\.(Match|Matches|Replace).*LongDescription|Regex\..*ProductName'

# 9. Stock custom.css written to (should be zero — brand CSS belongs in <customer>_custom.css; any file named
#    exactly custom.css is Swift-shipped sample code per re-skin.md §What NOT to touch)
git diff --name-only -- '*custom.css' | Select-String -Pattern '(^|[\\/])custom\.css$'
git log --name-only --pretty=format: -- '*custom.css' | Select-String -Pattern '(^|[\\/])custom\.css$' | Select-Object -Unique
# (second command catches already-committed writes — the baseline-import commit is the only sanctioned hit)
```

### Interpretation

| Grep | Hit means | Remediation reference |
|------|-----------|-----------------------|
| #1 | Raw DB access in a paragraph template | §"Pricing" / §"Orders" / §"Products" / §"User identity / groups" above |
| #2 | Routing-by-URL-string | §"URLs" |
| #3 | Project-locked URL string | §"URLs" (use `GetPageIdByNavigationTag`) |
| #4 | Legacy URL synthesis | §"URLs" |
| #5 | Marketing-fragile branching | §"Custom item types" → "Things to NEVER do" + §"Per-category behavior" |
| #6 | Shim instead of custom item type | §"Custom item types — the `<Prefix>_*` discipline" |
| #7 | Cache-buster-breaking inline include | [`re-skin.md`](re-skin.md) §"Wiring up project-scoped custom.css" |
| #8 | Brittle content-extraction regex | §"Product field arrays / lists" |
| #9 | Brand CSS written into Swift's shipped `custom.css` sample | [`re-skin.md`](re-skin.md) §What NOT to touch — revert, move rules to `<customer>_custom.css` |

## Cross-references

- [`re-skin.md`](re-skin.md) §"Pre-escalation check — search `dw10source` first" — uses this file as the lookup table; §"Re-skin smell" — the shim symptom that the custom item-type discipline fixes.
- [`paragraphs.md`](paragraphs.md) — Swift's stock paragraph types and the empty-`ParagraphTemplate` alphabetical-fallback hazard (a `<Prefix>_*` variant cshtml interacts with this).
- [`customer-center.md`](customer-center.md) — the CSR section uses the Permission store for its group-gated subtree; do not re-implement the gate.
- [`integrity-sweep.md`](integrity-sweep.md) Check 7 — the gating subset (raw DB access only) of the grep pack above.
- [`../../dynamicweb-demo-base/references/customisations.md`](../../dynamicweb-demo-base/references/customisations.md) §"What the rule *actually* forbids vs. doesn't forbid" — scope clarification for subscribers / helpers / item-type XMLs.
