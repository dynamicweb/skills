# Keying an ERP feed

## Contents

- [The decision that has to be made before the first load](#the-decision-that-has-to-be-made-before-the-first-load)
- [Products: key on the product number](#products-key-on-the-product-number)
- [Groups and customers: the name is the key](#groups-and-customers-the-name-is-the-key)
- [Order export: the shipped template needs three casing fixes](#order-export-the-shipped-template-needs-three-casing-fixes)
- [Prove it with a second identical run](#prove-it-with-a-second-identical-run)

> How to key an ERP feed so it updates the existing catalogue in place instead of duplicating or
> re-minting it. The provider mechanics behind each rule are owned by
> [`../../dw-integration-framework/references/provider-behaviour.md`](../../dw-integration-framework/references/provider-behaviour.md);
> this reference is the ERP-side decision. Loaded from the SKILL.md "Deep reference" table.

## The decision that has to be made before the first load

An ERP feed usually arrives with a natural key of its own — an item number, a customer account
number, a category code — and no Dynamicweb id. Two questions settle the whole integration, and
both are cheap now and expensive later:

1. **Does the feed update the existing catalogue, or create alongside it?** Answered by which
   destination column the natural key is mapped to.
2. **Do the created rows need source-derived ids?** Answered before the first load, because
   re-keying afterwards is a cross-table migration.

Both are configured on the activity's column mapping (MCP `save_integration_activity_mapping`, or
the mapping tab in the admin activity editor).

## Products: key on the product number

The Ecom destination resolves an incoming row against existing products in the order
**`ProductId`, then `ProductNumber`, then `ProductName`**. So a feed carrying no Dynamicweb id
updates hand-authored products in place when its natural key is mapped to **`ProductNumber`** —
which is the default keying recipe for any ERP feed running against a catalogue that already
exists.

**If stable, source-derived ids are wanted** — because a downstream system, a URL scheme or a
manual admin workflow references the ERP's own code — map the source key onto `ProductId` (and the
source category key onto `GroupId`) **before the first load**. Rows the provider creates otherwise
get minted sequential `ImportedPROD<n>` / `ImportedGROUP<n>` ids: the `CreateMissing*` flags control
whether the row is created, never what id it gets. Where the storefront's product URLs are
name-slug based the minted id never surfaces to a shopper, which is a legitimate reason to accept
it — decide deliberately rather than by default.

**Re-key by delete-and-reload**, never by mapping a new `ProductId` onto an existing feed row: the
in-place re-key carries the group relations and orphans every category field value.

**Expect the primary-group flag to be lost, not just unset.** A product import clears
`GroupProductRelationIsPrimary` on every product that sits in more than one group — which includes
any product that also sits in a PIM data-model group — on every run. Where breadcrumbs or a
canonical group matter, snapshot the flag before the run and replay it afterwards. And author
`PrimaryGroup` as a **plain unquoted group id**; the quoted-CSV form the provider itself exports is
accepted by the groups column and never matches the primary-group write, producing zero primaries
across the whole feed.

## Groups and customers: the name is the key

A customer import keys on the **group name**. That makes the name an identity string rather than a
label: keep the exact characters the source system emits, punctuation and all. Normalising a name
to plainer ASCII in the payload forks a duplicate account tree on the next run instead of matching
the existing groups.

The same rule reaches group membership. Membership rides a single CSV column of group names or ids
that the user provider expands additively into relation rows, so a membership that has to be
*derived* from another value belongs in the source XSLT — there is no lookup at the mapping layer.

## Order export: the shipped template needs three casing fixes

The platform's shipped `ErpOrderExport.xml` quick-setup template predates 10.28.x. On 10.28.x the
order provider resolves columns against the live `EcomOrders` / `EcomOrderLines` casing, so exactly
three of the template's columns no longer match:

| In the shipped template | On 10.28.x |
|---|---|
| `OrderID` | `OrderId` |
| `OrderLineID` | `OrderLineId` |
| `OrderLineOrderID` | `OrderLineOrderId` |

Every other column in the template still matches. Two amounts in the same activity also need
attention: **`OrderLineUnitPrice` comes through empty** — `OrderLineUnitPriceWithoutVAT` carries the
number — and for the header amount use `OrderPriceWithVAT` rather than the dead legacy
`OrderTotalPrice`.

Assert the exported rows carry **non-empty amounts**, not just a row count: an export that writes
the right number of rows with zero money in them logs as a clean success.

## Prove it with a second identical run

Idempotency is the assertion that proves the keying resolved the way you think it did. Run the
update payload twice back to back and diff the destination tables: a second run that changes zero
rows proves the feed matched existing rows rather than minting new ones. A run that adds rows on
the second pass means the key did not resolve, whatever the first run's counts looked like.
