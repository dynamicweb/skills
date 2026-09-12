# The two-directional ERP mock

## Contents

- [What this flavor is for](#what-this-flavor-is-for)
- [The four activities](#the-four-activities)
- [The four platform mechanisms that remove the custom code](#the-four-platform-mechanisms-that-remove-the-custom-code)
- [Value-idempotence: seed the staging tables FROM the live rows](#value-idempotence-seed-the-staging-tables-from-the-live-rows)
- [The reset, and the trap that only shows up in the ERP's number series](#the-reset-and-the-trap-that-only-shows-up-in-the-erps-number-series)
- [The real-vs-staged inventory](#the-real-vs-staged-inventory)
- [Swapping in a live tenant](#swapping-in-a-live-tenant)

> A third flavor beside the one-direction DB-staged recipe in [mock-deltas.md](mock-deltas.md): a
> round trip that shows orders LEAVING the portal and an ERP document number COMING BACK, built
> entirely from shipped providers. Loaded from the SKILL.md "Where to find things" table.

## What this flavor is for

The DB-staged recipe stages one **inbound** direction and narrates it. A beat that has to show the
round trip — the order leaves, the ERP answers with its own document number, the status flips on the
customer's order list — needs activities in both directions, and the instincts that reach for a
custom provider class, a custom order field for the ERP's number, or a `ShopType=3` channel for the
ERP are all wrong. **Everything this needs is shipped**: four activities, one task folder, zero
DLLs, zero notification subscribers, zero rows on the customisations ledger.

Use it when the demo must run the sync on camera in both directions. Use
[mock-deltas.md](mock-deltas.md) when one inbound direction and an admin screen carry the story.

## The four activities

Each is a source provider + destination provider + mapping — configuration only.

| # | Activity | Source | Destination |
|---|---|---|---|
| 1 | Sales order export | DW `OrderProvider` | `SqlProvider` over the staged ERP header/line tables |
| 2 | Order confirmation (document number back) | `SqlProvider` over a staged confirmation view | DW (`EcomOrders`) |
| 3 | Item price and inventory inbound | `SqlProvider` over the staged item / inventory / price tables | `EcomProvider` |
| 4 | Service order export (from approved claims) | `SqlProvider` over a staged claim-queue view | `SqlProvider` |

The staged ERP tables live in the solution's own database, so no `SqlProvider` needs an external
connection — but a `SqlProvider` **source** still has to carry a literal connection string, because
the empty-node default-connection fallback is destination-only. Name a local instance relatively
(`Server=.\<instance>`) so the job file publishes no host name; the full rule is in
[`../../dw-integration-framework/references/job-file-format.md`](../../dw-integration-framework/references/job-file-format.md#sqlprovider-connection-nodes).

Keep all four tasks in **one folder** so the presenter opens the pair as one integration story.

## The four platform mechanisms that remove the custom code

| Mechanism | What it replaces |
|---|---|
| `OrderProvider.OrderStateAfterExport` | A notification subscriber for the status flip. The order moves to a net-new state the moment the export succeeds, and a stock Swift order list already renders the state name in a coloured badge — the flip shows on the storefront with **no template change**. |
| `ExportOnlyOrdersWithoutExtID` + `ExportNotExportedOrders` + `DoNotExportCarts` | A hand-written export filter. Seeded historical orders that already carry an ERP number are skipped. (Note it does **not** exclude ledger entries — see the order-provider section of the framework reference.) |
| `EcomOrders.OrderIntegrationOrderId` / `OrderIsExported`, surfaced as `OrderViewModel.IntegrationOrderId` | A custom order field for the ERP's document number. Activity 2 writes it back, so DW does not name the document — the ERP does. Hand-made order fields carry their own trap family; these columns are shipped. |
| `EcomProvider` destination with `UpdateOnlyExistingProducts` + `UpdateOnlyExistingRecords` + `UseStrictPrimaryKeyMatching = True`, and every `RemoveMissing*` / `DeactivateMissingProducts = False` | A safety review. The inbound activity **cannot** create, delete or deactivate a product. |

## Value-idempotence: seed the staging tables FROM the live rows

Seed the staged ERP tables from the live Dynamicweb rows, so a run **re-asserts** the ERP's numbers
rather than inventing them. The inbound activity then touches every product, stock unit and price
row and leaves the catalogue size, the price-matrix checksum and the per-location on-hand counts
unchanged — which is what lets the presenter run the sync repeatedly without the demo drifting.

Map per-location on-hand in the same activity as the product-level stock so one inbound run repairs
**both** stock numbers; a run that fixes only one leaves the storefront and the admin disagreeing.

When the inbound activity writes extended or global product fields, pair it with the
`ProductService` cache flush — see [mock-deltas.md](mock-deltas.md) "Option 3".

## The reset, and the trap that only shows up in the ERP's number series

The reset for this flavor is where a one-direction reset recipe breaks, because the outbound half
has state the inbound half does not.

- **Never null an integration key as a reset step.** `OrderIntegrationOrderId` *is* the
  already-exported flag: clearing it does not reset the demo, it re-arms the export for every row it
  touches. With seeded history in place the next export sweeps all of it, the ERP number series
  jumps by the length of that history, and the order placed on stage is minted hundreds of numbers
  away from what the assertions expect. Give every seeded row a **plausible historical ERP document
  number** instead, so it is already processed, and park the number series so the live order simply
  continues the sequence.
- **Scope the reset by a marker column the generator stamps on every row it creates** — never by an
  id list, an id range or a date, all of which seeded history also matches. An id-list exclusion is
  correct while seven orders exist and becomes wrong silently the moment history is seeded.
- **Give seeded aggregate history a persona-invisible marker** (an unowned customer id) so it can
  never surface in a persona's own order list.
- **Re-run the integration beat after widening a reset, not just the state assertions.** The damage
  lives in the external number series, which no state assertion looks at.
- Two assertions catch a re-arming reset, and only together: after the reset the seeded-history row
  count is **unchanged**, and the export-eligible count is **exactly zero**. After the live beat:
  exactly one exported document, and the next document number is the expected one.

Restore ordering (purge first, then restore) is owned by
[`../../dw-integration-framework/references/provider-behaviour.md`](../../dw-integration-framework/references/provider-behaviour.md#restores-and-resets-built-on-activities).

## The real-vs-staged inventory

Ship the recipe with an honest inventory, because a presenter will be asked "is this real?".

| Real | Staged |
|---|---|
| The Integration Framework, the shipped providers, the activities, the mappings, the scheduled tasks, the run logs, the order state transition, and the writeback columns | The ERP itself — a handful of tables, sequences and triggers in the same database |

Assert the always-on rule as part of the gate: **zero** `EcomShops` rows and **zero** `EcomFeed`
rows for the ERP. If either is non-zero the demo has drifted back into the channel/feed
mismodelling that [integration-framework.md](integration-framework.md) exists to prevent.

## Swapping in a live tenant

On a live tenant only the source/destination **provider** changes: the activities, the mappings, the
schedules and every storefront surface stay exactly as they are. That is the point of building the
mock this way, and it is also the honest answer to "what would it take to make this real". The live
path is [`../dw-integration-bc/SKILL.md`](../../dw-integration-bc/SKILL.md).
