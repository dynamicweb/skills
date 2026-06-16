# integration-framework.md

> The canonical "source+target, NOT channel/feed" rule. Loaded from `dynamicweb-erp-demo/SKILL.md` "Always-on rule" and "When to use this skill". Read before deciding how to model an ERP in any Dynamicweb demo.

## The rule, one sentence

**An ERP in DW10 is modelled through the Integration Framework as both a source AND a target -- never as an `EcomShops.ShopType=3` channel and never as an `EcomFeed`.**

## What the DW docs actually say

From [doc.dynamicweb.com](https://doc.dynamicweb.com/) (Integration area, Integration Framework v2):

- "Data integration is the process of importing and exporting data to and from your Dynamicweb solution, either on an ad-hoc basis, on a schedule or in real-time."
- The Integration Framework v2 is "a collection of components for transferring data and maintaining data consistency between a Dynamicweb solution and a remote system. **This is typically an ERP.**"
- "An integration provider is a piece of software for moving data between Dynamicweb and an external data source, like an XML file, a CSV file or an SQL database."
- An activity requires two provider types: "**A source provider matching the data source**" and "**A destination provider matching the data destination**."
- Three approaches: **ad-hoc activities**, **batch integration** (scheduled tasks at hourly/daily/weekly intervals), and **live integration** ("retrieves data from a remote system in real-time, and uses it to show for instance live prices or stock states").

## Source vs target -- which is the ERP?

It depends on the direction of the activity. Across the bidirectional set of activities that make up an "ERP integration", the ERP is BOTH a source and a target.

| Direction | Source | Target | Typical payload |
|---|---|---|---|
| BC -> DW | ERP (BC) | Dynamicweb (Ecom/Products) | Price, stock, cost, vendor item no, reorder status, customer-specific contract prices |
| DW -> BC | Dynamicweb (Ecom/Products) | ERP (BC) | New-product descriptive data, enrichment updates, marketing copy, attribute values |

A given **activity** has exactly one source and one target. The "ERP is source AND target" rule applies at the integration-level (the collection of activities), not at the activity-level.

## The right modelling shape in DW10

For both flavors of this skill (mock + live), the modelling shape is the same -- only the implementation differs.

```
Activity (one per direction)
    Source provider     -> data source (BC for BC->DW; DW for DW->BC)
    Destination provider -> data target (DW for BC->DW; BC for DW->BC)
    Field mapping       -> how source fields map to destination fields
    Schedule            -> ad-hoc | batch (cron) | live (per request)
```

Concretely:

- **Live flavor** (sister skill `dynamicweb-pim-for-bc`): the AppStore "PIM for Business Central connector" registers BC-side endpoints under `/admin/api/BC*` (11 queries + 4 commands). BC polls these on its own schedule; DW responds with the requested data shape. The connector itself is the destination provider FROM BC's perspective; the queries are the source endpoints FROM BC's perspective. See [`../dw-integration-bc/references/connector-endpoints.md`](../../dw-integration-bc/references/connector-endpoints.md).
- **Mock flavor** (this skill, [mock-deltas.md](mock-deltas.md)): no provider class is registered. The database is pre-staged into the **post-BC-sync state** â€” every value BC would have written is already in `EcomProducts`, as if the delta arrived overnight â€” and a single built-in `RunSqlScheduledTaskAddIn` RESET task flips it back between demos. The demo narrates "BC sent us this; look at the result", with the data + action-rule definition + email template as evidence. The PIMâ†’BC direction is told via one static field-mapping artefact. The framework concepts (source provider, destination provider, activity, field mapping) are narrated against that staged state, not against live wires. (Superseded 2026-05-21: an earlier version of this flavor used inbox/outbox JSON files â€” see the "Do not" section of mock-deltas.md.)

The mock flavor is a model of the framework, not a bypass of it. The whole point is to make the framework's shape visible without requiring a live BC tenant.

## Anti-patterns (don't do this)

### Anti-pattern 1: ERP as a `ShopType=3` channel

**Wrong.** "Let's create a shop called BC with `ShopType=3` and a group tree, and publish products into it as a feed."

**Why it's wrong.** `ShopType=3` channels are feed publishing targets for read-only external consumers (Shopify, HD, OrderEase, PackGenie, EDI partners). They have their own group tree because products get *related into* those groups to control what the feed publishes. The channel never writes back to DW. An ERP writes back -- price updates, stock changes, reorder status -- and those writes need to land on DW products, not on a separate channel's group tree.

**What it breaks.** The product-page admin UI splits "Groups/Channels" vs "Data Models" based on the parent shop's UsageType. A BC channel would appear under "Groups/Channels" and its group memberships would be modelled as feed-publishing memberships, when really BC isn't publishing anything -- BC is exchanging data with the same products that live under SHOP1. You end up with phantom group memberships that exist only to satisfy the channel-mapping mental model and don't represent anything real.

### Anti-pattern 2: ERP as an `EcomFeed`

**Wrong.** "Let's create a feed called `BC-Out` with a query that picks up changed products and posts them to BC."

**Why it's wrong.** `EcomFeed` is a frontend module config row -- it's the wiring that lets the `eCom_Feed` paragraph type render a feed XML/JSON output for a public URL that an external system polls. Feeds are read-only HTTP endpoints; they have no concept of a destination provider, no field mapping table, no scheduled push, no error handling for "BC was unreachable". Trying to use a feed as the DW->BC push channel is square-peg-round-hole.

**What it breaks.** Feeds run per-request (when BC GETs the feed URL); they have no schedule of their own. The PIM doesn't know whether BC consumed a given delta. Feed XML is positional and lossy; the framework's field-mapping table is explicit and lossless. And feeds don't survive a customisation audit -- they're frontend config, not integration code.

### Anti-pattern 3: ERP sync via a custom controller polling + raw SQL

**Wrong.** "Let's add `Controllers/BcSyncController.cs` that polls BC's REST API every 5 minutes and writes results via `UPDATE EcomProducts SET ProductPrice = ...`."

**Why it's wrong.** Raw SQL bypasses every domain service hook. Price changes need to invalidate `Dynamicweb.Ecommerce.Prices` cache; stock changes need to refresh the Products index; both need to fire DW's notification pipeline so any `NotificationSubscriber` on `Ecommerce.Product.AfterSave` or similar runs. The framework's destination provider does all this for you. The custom controller does none of it, and the failure mode is "the DB row updated but the storefront still shows yesterday's price" -- which surfaces 20 minutes into the demo when someone refreshes a PDP.

**What it costs.** A custom controller adds a row to `CUSTOMISATIONS.md` (per the customisations-ledger preflight) and you have to defend it in the customisation-budget pitch beat. A framework provider is config, not code -- no ledger row needed.

## What the framework looks like in code (live flavor)

For Dynamicweb's live BC flavor, the framework registration is split:

- The AppStore "PIM for Business Central connector" package ships the provider classes (in the AppStore install folder under `wwwroot/Files/System/AddIns/Installed/`). You don't write these yourself.
- DW's `BCSetupUpdateProvider` populates default settings (`indexBuildKey`, `buildName`, `workflowStateId`) that have to be corrected per-demo -- see [`../dw-integration-bc/references/dynamicweb-connector-settings.md`](../../dw-integration-bc/references/dynamicweb-connector-settings.md).
- The framework wires BC -> `/admin/api/BC*` queries (BC is source, DW is destination via the connector's destination provider) and DW -> BC (the connector's source provider reads from DW Products + posts to the BC endpoint).

You don't see the framework as "an Activity row in a UI grid" in this flavor -- the AppStore connector hides that surface. But conceptually it's there: source provider, destination provider, mapping, schedule. The `/admin/api/BC*` surface IS the framework, exposed to BC's side.

## Cross-references

- Mock flavor end-to-end: [mock-deltas.md](mock-deltas.md).
- Generic ERP data shape (which fields ERP writes vs reads): [erp-data-shape.md](erp-data-shape.md).
- Scenarios-first planning to scope an ERP integration before building: [scenarios-first-planning.md](scenarios-first-planning.md).
- Live flavor (ngrok + AppStore connector + `/admin/api/BC*`): [`../dw-integration-bc/SKILL.md`](../../dw-integration-bc/SKILL.md).
- Channel-vs-shop pedagogy beat (ShopType enum, why ShopType=3 is feeds not ERPs): [`../dw-demo-pim/references/structural-model.md`](../../dw-demo-pim/references/structural-model.md) Â§2.1.



