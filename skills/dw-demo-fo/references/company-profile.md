# Company profile: what a demo company can and cannot borrow from a customer's F&O

## Contents

- [The boundary: per-company vs tenant-wide](#the-boundary-per-company-vs-tenant-wide)
- [What that buys, and the sentence to say out loud](#what-that-buys-and-the-sentence-to-say-out-loud)
- [From discovery brief to profile](#from-discovery-brief-to-profile)
- [The seven profile sections](#the-seven-profile-sections)
- [Modelling the spine identifier](#modelling-the-spine-identifier)
- [Where the profile lives](#where-the-profile-lives)

## The boundary: per-company vs tenant-wide

A legal entity is a **configuration and data** boundary, not a schema boundary. Everything on the left can
differ per demo company in one shared sandbox; everything on the right is one shared value for the whole
environment and cannot be tailored per demo.

| Per legal entity (tailorable) | Tenant-wide (shared by every company) |
|---|---|
| Ledger, currency, fiscal-year link, posting profiles | Chart of accounts, fiscal calendars, financial-dimension **definitions** (values can be company-scoped) |
| Number sequences and their formats (item, customer, sales order and so on) | Tables, data entities, extension fields, no-code **custom fields** |
| Module parameters (inventory, sales, AR, procurement) | X++ models and any deployed package, including the F&O plugin |
| Sites, warehouses, warehouse locations | Products (the shared product master), product attributes and attribute groups |
| Item groups, item model groups | Category hierarchies and their categories, **storage and tracking dimension groups** |
| Released products (the per-company face of a shared product) | Units of measure, languages, countries |
| Customers, customer groups, terms of payment, delivery terms | Address books and the global address book |
| Price/discount groups and trade agreements | Users, roles, security configuration, Entra app registrations |
| Sales orders, quotations and every other transaction | Feature management, batch framework, MCP client allow-list |

**Do not trust the table when it matters: ask the environment.** Entity metadata carries the answer
directly: `RootTableIsGlobal` is `true` for a tenant-wide table and `false` for a company-scoped one, and a
company-scoped entity also exposes a `dataAreaId` field. Over the F&O MCP server that is
its `data_get_entity_metadata` tool on the entity set; over OData the same fact shows up as the presence of
`dataAreaId` on the entity. Check any object the profile is about to claim as per-company before writing it
down; the split is not always where intuition puts it. Verified this way: released products and customer
groups are company-scoped; legal entities and **tracking dimension groups** are global, so a serial-tracking
group invented for one demo is visible to every company in the sandbox and has to carry the company prefix
like any other shared object.

Two consequences that decide how a profile is written:

1. **The catalog is shared.** Product numbers, attributes and categories created for one demo are visible to
   every other company in the sandbox. Prefix them with the demo's company code
   ([shared-sandbox.md](shared-sandbox.md)).
2. **Custom fields and ISV behaviour cannot be reproduced.** If the discovery brief found an ISV table or a
   customer-specific field carrying meaning, the demo approximates it with standard machinery (an attribute,
   a dimension, a tracking serial), and the approximation is named as one.

## What that buys, and the sentence to say out loud

What the audience recognises as "their ERP" is almost entirely on the left column: their item numbers look
like their item numbers, their orders carry their prefix, their machines, vehicles or units are tracked by the
identifier they actually use, their sites and warehouses have their names, their customer groups match their
segmentation. That is a large majority of the felt realism, and none of it is customisation.

Wording rule:

> **"Configured like yours, not your customisations."**

Say the demo company is **configured from the shape we found in your environment**: numbering, dimensions,
sites, groups, catalog structure. Do not say, or let the audience infer, that it carries their customisations,
their ISV modules, or their custom fields. If asked directly: those are schema-level and tenant-wide; adding
them is a development project, and the discovery brief scopes it.

## From discovery brief to profile

An F&O discovery of the customer's environment produces a data-model brief and a question list. The
profile is the subset of that brief which is (a) per-company and (b) visible in the demo. Map it straight across:

| Discovery output | Profile section |
|---|---|
| Spine identifier (the central number the processes hang off) and its tracking-dimension semantics | §4 Spine identifier |
| Number-sequence formats read from the process footprint | §2 Numbering |
| Populated entities per legal entity (census) | §5 Catalog, §6 Customers (what to seed and how much) |
| Storage/tracking dimension groups, sites and warehouses in use | §3 Inventory dimensions and locations |
| Item / customer group vocabulary | §5, §6 |
| ISV and custom entities found without a standard equivalent | §7 Not reproduced (with the approximation used) |
| Anything inferred rather than observed | carried over with its `[to confirm]` tag |

If there is no discovery brief (internal demo, no customer environment), the profile is written from the demo
story instead and every line is marked as invented. Both are legitimate; conflating them is not.

## The seven profile sections

The template is [`assets/templates/company-profile.md`](../assets/templates/company-profile.md). Sections:

1. **Identity**: company code (4 characters at most), name, country/region, language, currency, primary address.
2. **Numbering**: number-sequence formats for the ids the audience will read on screen: item, customer,
   sales order, quotation, packing slip, invoice. Continuous vs non-continuous, and whether lower numbers are
   allowed (seeding needs them).
3. **Inventory dimensions and locations**: storage dimension group, tracking dimension group, sites,
   warehouses; which dimensions are active on the products the demo shows.
4. **Spine identifier**: the customer's central number, how it is modelled, and what it drives in DW.
5. **Catalog**: item groups, item model groups, category hierarchy name, attribute set, how many released
   products and of what kind, unit of measure.
6. **Customers and pricing**: customer groups, terms, delivery terms, price/discount groups, which customers
   map to which DW user groups.
7. **Not reproduced**: every ISV/custom element from discovery that this company approximates or omits, with
   the approximation and the sentence to use if it comes up.

## Modelling the spine identifier

Most customer processes hang off one identifier: a hull, vehicle or machine number, a batch, a configuration
code. Reproducing it is the highest-value thing the profile does, and standard F&O usually has a home for it:

| Spine shape found in discovery | Standard modelling in the demo company |
|---|---|
| A per-unit serial the customer tracks for life (hull/vehicle/machine number) | **Tracking dimension group** with Serial number active; serial numbers created per unit; serial-controlled released products |
| A per-unit number the customer *assigns* at manufacture | same, plus a number sequence whose format matches the customer's mask |
| A batch/lot identifier | Tracking dimension group with Batch number active |
| A configuration/variant code | Product dimensions (configuration/size/colour/style) on a product master |
| A site- or location-scoped identifier | Storage dimension group with Site/Warehouse (and Location where the demo shows it) |
| An ISV-owned key with no standard equivalent | Approximate with a product attribute or an external-reference field, and list it in §7 |

State in the profile what the identifier drives on the DW side (search, unit detail, warranty lookup,
service history), because that is what determines whether serial-level fidelity is needed or a plain product
number would do.

## Where the profile lives

`demo-companies/<slug>/company-profile.md` in the engagement folder (or the demo folder's equivalent),
alongside the seed scripts and the run log. Customer-identifying facts stay there: never in this skill and
never in the plugin ([`../../dw-demo-foldback/references/fold-back-workflow.md`](../../dw-demo-foldback/references/fold-back-workflow.md)
"Sanitize the candidate content").
