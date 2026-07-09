# DW10 canonical surfaces — router

> The "use X, not Y" cheat sheet for the DW10 surfaces that get re-implemented in Razor. This file is
> now a **router**: the vendor-generic surface inventory has been folded up into the foundational
> candidates. Use this page to find the right candidate for the surface you're about to re-implement.
>
> **Why this exists.** Every "fake pattern" in a Swift demo (raw SQL probes on
> `AccessUserGroupRelation`, hard-coded area prefixes, master-template `WriteLiteral` redirects,
> `EcomOrders` SQL chains in Razor) is a workaround for a surface the demo author didn't know was
> there. When in doubt, search a local clone of the DW10 source (location per machine — ask/discover, never hardcode) for the canonical surface
> before writing SQL or parsing URLs. Cross-references the escalation ladder in [`re-skin.md`](re-skin.md).

## Surface → owning candidate

| Surface you're about to hand-roll | Use instead — owned by | Candidate |
|---|---|---|
| Read user / user groups (`Pageview.User`, `Pageview.User.GetGroups()`) | `dw-render-viewmodels` | [`render-viewmodels.md`](../../dw-demo-base/references/foundational/render-viewmodels.md) "User identity / groups" |
| Gate a Page/Paragraph by role or group (the permission entity store — `UnifiedPermission` rows keyed `PermissionName='Page'`/`'Paragraph'`; group gates need the broad-role deny pair; NOT the legacy `*Permission` columns) | `dw-users-permissions` | [`users-permissions.md`](../../dw-demo-base/references/foundational/users-permissions.md) §15 |
| Read prices (`Services.Prices`, custom `PriceProvider`) | `dw-commerce-catalog` | [`commerce-catalog.md`](../../dw-demo-base/references/foundational/commerce-catalog.md) §2.12 |
| Read customer orders (`Services.Orders.GetCustomerOrdersByType` / `GetOrdersBySearch`) | `dw-commerce-orders` | [`commerce-orders.md`](../../dw-demo-base/references/foundational/commerce-orders.md) "canonical order read surface" |
| Get product / friendly URLs; `AddStylesheet`/`AddScript` hoisting; cross-cutting redirects (`Page.Loaded` subscriber); per-category behavior; product-field arrays | `dw-render-razor` | [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §1 |
| `ViewModelTemplate<>` Razor pitfalls (`@Html.Raw` absent, `ProductFieldValues`, `ToggleFavorite`) | `dw-render-razor` | [`render-razor.md`](../../dw-demo-base/references/foundational/render-razor.md) §2 |
| Custom item types — the `<Prefix>_*` discipline | `dw-content-modelling` | [`content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md) §2 |

## Legacy dotted-path redirects (`.htm` / `.asp`) — IIS-only; don't fail the polish gate on localhost

Seeded 301 redirects from legacy URLs (e.g. a Volusion migration) behave differently on the dev host than in production, and it reads as "redirects are broken" during polish when it isn't:

- **Extensionless stems 301 correctly on the Kestrel dev host** — `GET /<legacy-stem>` → 301 to the new URL.
- **Literal `.htm` / `.asp` rows 404 on Kestrel** — ASP.NET Core drops dotted paths before DW's redirect provider sees them. On **production IIS the same rows reach the provider and 301** as intended.

So: **store the literal `.htm` / `.asp` rows for production, demo the extensionless stems on localhost.** The polish gate must assert the extensionless stems 301 on the dev host and must **not** fail on dotted-path 404s — flag those as IIS-only rows, not defects. One sentence in the runbook saves the "redirects are broken" scare during a local polish pass.

## Discipline audit — grep pack (run before "ready" / before fold-back)

The one-shot grep pack that verifies a Swift demo's templates against the canonical surfaces is owned
by `dw-swift-building` — staged in
[`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §10.

**TRIGGER — run the grep pack:**

- Before declaring a demo "ready" (end-of-build budget review).
- Before folding learnings back into the plugin (so the plugin's reference docs aren't carrying
  lessons the active demos haven't applied).
- After any escalation up [`re-skin.md`](re-skin.md) Tier 3+ — a `.cshtml` write is the most likely
  place to acquire one of these anti-patterns.

A clean run is the green light; each hit routes back to the owning candidate via the table in
[`swift-building.md`](../../dw-demo-base/references/foundational/swift-building.md) §10.
