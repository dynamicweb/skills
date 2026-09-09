# CPQ cards, quotes and the ERP boundary

What a configuration becomes once it is saved, how it reaches a Dynamicweb order, and exactly where
Business Central starts being required.

## Contents

- [The card is a quote header](#the-card-is-a-quote-header)
- [Card items and their BOM](#card-items-and-their-bom)
- [Card templates](#card-templates)
- [Revisions](#revisions)
- [The Dynamicweb order link](#the-dynamicweb-order-link)
- [CPQConfiguration](#cpqconfiguration)
- [The ERP boundary](#the-erp-boundary)
- [Versioning consequences](#versioning-consequences)

## The card is a quote header

A card is the document a configuration sits on. `CPQCard` carries `CardNumber`, `RevisionNumber`,
`CardType`, `CardSource`, `Name`, `Description`, `CardParameters`, `CustomerInfo`, `DWCartInfo`,
`PageNavigationTag` and timestamps.

`CardType` is **`Quote` or `Order`**, defaulting to `Quote`. `CardSource` distinguishes a card that
originated in Dynamicweb from one that came from an ERP; the column default is `ERP`, and the
frontend tests only for `ERP` and treats everything else as local. Read it as *ERP or not-ERP*
rather than as a strict enum, and do not rely on a particular local literal.

Nothing is enforced in the database — the CPQ tables carry only two foreign keys (card item to card,
BOM line to card item) and **no check constraints at all**. Values are conventions maintained by the
application.

## Card items and their BOM

`CPQCardItem` is one configured item on the card — for most models, one configured product.

| Column | Holds |
|---|---|
| `ItemNo` | the configured item's number |
| `ItemLineNo` | the line number, and the key to the linked Dynamicweb order line |
| `ProductionBomNo` | the production BOM number, once an ERP has created one |
| `ModelVersionId` | **the version this item was configured under** |
| `ClientInputsJson` | every answer that produced the configuration |
| `BomLines`, `BomTotals`, `RouteLines`, `RouteTotals` | the calculated result |
| `TotalSellPrice` | the line total |

`ClientInputsJson` is what makes a configuration reproducible: it is the complete input set, so
reopening a card replays the answers rather than reconstructing them.

`CPQCardItemBomLines` is the exploded, priced BOM — `LineSeq`, `ItemNo`, `Description`, `UOM`,
`GroupName`, `PricingMethod`, `ListPrice`, `CustomerDiscount`, `UnitCost`, `Qty`, `LineCost`,
`CostUpAmount`, `UnitSell`, `LineSell`, `DiscountType`, `DiscountAmount`, and the discounted
equivalents — plus `BCStatus`, `BCLineNo` and `BCItemNo`, which stay null until an ERP writes them.

## Card templates

`CPQCardTemplate` and `CPQCardTemplateItem` are the blueprint for a new card: a named template with
a label, description, max items, sort and enabled flag, holding items that each carry a key, label,
page navigation tag and a seed `ClientInputsJson`.

Creating a card from a template walks the enabled templates in sort order and inserts one card item
per template item, seeded from that template item's inputs. Use templates when a customer always
starts from one of a few known starting points rather than a blank configuration.

## Revisions

A revision is a **deep copy**. The engine reads the highest existing revision number for the card
number, creates a new header, then copies every card item and every BOM line beneath it. The card
number stays; the revision increments.

This is why a quote can be reconfigured without losing what was quoted before, and it is worth
demonstrating — most configurators cannot show you what changed between two versions of a quote.

## The Dynamicweb order link

A card item can be linked to a Dynamicweb order line, and the engine keeps the two in step.

The link is a pair: a **source order id**, held inside `CPQCard.DWCartInfo`, and the card item's
**`ItemLineNo`**. When both are present, the sync writes quantity, unit price, line price, product
name, variant text and comment onto the linked order line, then clears the relevant cache.

When either is missing the sync skips, logging *"missing source order id or item line no"*; when the
order line has gone it logs *"linked order line not found"*. Both are quiet — a card that silently
stops updating its order line has almost always lost one half of that pair.

Note the source order id is **not a column** on any CPQ table. It lives in the `DWCartInfo` JSON, so
a query looking for a column will not find it.

The cart, order and quote paths themselves are ordinary Dynamicweb: the engine creates a cart
through `/dwapi/ecommerce/carts/…`, adds items, and calls `createOrder`, passing quote flags when the
result should be a quote rather than an order.

## CPQConfiguration

A generic key/value side-store, keyed by a data type, a key and a key line, holding a JSON blob.
Two types are in use:

- **`DWCart`** — the cart/order linkage snapshot for a card.
- **`GVAR CARD`** — card-scoped variables, which is what `gvar[…]` reads. These rows are written with
  a model version id of `0`, i.e. deliberately version-agnostic, so a card-scoped variable survives
  a model version change.

## The ERP boundary

**A complete configurator runs with no ERP.** Local, always:

- All rule evaluation — input, BOM, route, price and output rules are SQL over the CPQ tables.
- **Pricing.** List prices come from the platform price service and `EcomProducts`. No price path
  calls an ERP.
- Cart, order and quote, through the Dynamicweb delivery API.
- Cards, card items, BOM lines, templates, revisions, configurations, quick-configure.
- **Document generation** — OpenXml `.docx`, written under the solution's own file store.

Business Central is required for exactly these, and each guards itself and returns early when no
connector is configured:

| Operation | What it creates in the ERP |
|---|---|
| Item card creation | the configured item |
| Production BOM create and refresh | the item's BOM |
| Routing | the production route |
| Sales quote header and lines | the sales document |
| Document attach | the generated document, stored against the ERP quote |
| Customer info refresh | *(a read)* customer header data from an ERP quote |

Two further notes. **PDF conversion is not a BC dependency** — it goes to Microsoft Graph, configured
separately, so a solution can want Graph credentials without wanting an ERP. And **one read path
depends on the ERP silently**: an input Lookup List whose data source is `odata` or `BC Lookup`
queries the connector, and with none configured it renders an empty option list and no error. See
[rules-and-lookups.md](rules-and-lookups.md).

The connector itself is not a bespoke client — it rides the platform's Integration Framework
endpoints, so authentication and endpoint management are configured there rather than inside CPQ.
`CPQConnector` holds the endpoint reference, environment and company. The ERP target is *also* a
per-model-version setting, so a version with no data connection fails ERP operations exactly as if
no connector existed at all.

**Plan the ERP as a later increment, not a prerequisite.** Because the BC columns on the BOM lines
stay null until a connector exists, connecting one fills them in — the model, the rules and the
cards do not change.

## Versioning consequences

`CPQCardItem.ModelVersionId` records the version each item was configured under, so reopening an old
card reloads the rules it was built with. That is the behaviour you want, and it has a sharp edge:
the *page* the card reopens on is resolved separately, by navigation tag, and may be pinned to a
different version.

A `CPQ_Page` is pinned to one immutable `ModelVersionId`. Publishing a new version does not move
existing pages; each must be re-pointed by hand. The picker labels versions by model name only, so
two versions of one model are indistinguishable in the dropdown — check the stored id rather than
trusting the label.

Deleting a model cascades manually and there is no foreign key protecting it, so a live page can end
up pointing at a version id that no longer exists.
