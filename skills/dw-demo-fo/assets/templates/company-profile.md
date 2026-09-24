# Company profile: <Demo name>

> Fill one of these per demo, in the engagement folder (`demo-companies/<slug>/company-profile.md`).
> Every line is either **[observed]** (traced to a discovery finding; name the source), **[to confirm]**
> (inferred, has a matching clarification question), or **[invented]** (no customer environment in scope).
> Keep customer-identifying facts here; never copy them into the skill or the plugin.

**Source brief:** `<path to the discovery data-model brief, or "none: internal demo">`
**Tenant / environment:** `<environment url>` · **Golden or donor company:** `<CODE>`
**Connection mode:** OData-only (the F&O plugin is parked; see connection-modes.md)
**Seeded from:** golden package `<file>` | Copy into legal entity from `<CODE>`

---

## 1. Identity

| Field | Value | Evidence |
|---|---|---|
| Legal entity id (4 characters at most) | `<CODE>` | |
| Name | | |
| Search name (`NameAlias`) | | |
| Country/region | | |
| Language | | |
| Currency | | |
| Primary address | | |

## 2. Numbering

The ids the audience reads on screen. Note continuous vs non-continuous and whether lower numbers are allowed
(seeding usually needs them).

| Sequence | Format | Continuous? | Evidence |
|---|---|---|---|
| Item / product number | | | |
| Customer account | | | |
| Sales order | | | |
| Quotation | | | |
| Packing slip / invoice | | | |

## 3. Inventory dimensions and locations

| Item | Value | Evidence |
|---|---|---|
| Storage dimension group | | |
| Tracking dimension group | | |
| Active dimensions on demo products | | |
| Sites | | |
| Warehouses | | |
| Warehouse locations shown in the demo? | | |

## 4. Spine identifier

The customer's central number: what everything else hangs off.

| Question | Answer |
|---|---|
| Identifier | |
| Format / mask | |
| Modelled in F&O as | |
| Assigned by | |
| What it drives in the DW front end | |
| Fidelity needed (serial-level vs product-level) | |

## 5. Catalog

| Item | Value | Evidence |
|---|---|---|
| Item groups | | |
| Item model groups | | |
| Unit(s) of measure | | |
| Category hierarchy name (prefixed `<CODE>`) | | |
| Product attributes / attribute group (prefixed) | | |
| Released products to seed (kind and count) | | |
| Variant / configuration model, if any | | |

## 6. Customers and pricing

| Item | Value | Evidence |
|---|---|---|
| Customer groups | | |
| Terms of payment / delivery terms | | |
| Price and discount groups | | |
| Customers to seed (who they represent) | | |
| Mapping to DW user groups | | |

## 7. Not reproduced

Everything discovery found that this company cannot carry (ISV modules, custom fields, extension tables,
customer-specific behaviour), with the approximation used and the sentence to say if it comes up.

| Found in the customer's environment | Why it cannot be reproduced | Approximation in the demo | What to say |
|---|---|---|---|
| | tenant-wide / schema-level | | |

---

## DW side

| Item | Value |
|---|---|
| DW install (local / hosted) and version | |
| Shops / channels involved | |
| Which jobs run, and their `dataAreaId` pin | `cross-company=true&$filter=dataAreaId eq '<CODE>'` |
| Front-end surfaces the ERP data appears on | |

## Build log

| Step | Route used | Notes |
|---|---|---|
| Legal entity created | OData / copy project / UI | |
| Configuration seeded | golden package import / Copy into legal entity | which package or templates, what failed |
| Copy gaps repaired (copy route only) | Repair-CopyGaps.ps1 / UI | bank, payment, dimension values, ledger parameters |
| Profile applied | | which steps needed a UI wizard |
| Data seeded | | script names |
| Verified | Test-DemoCompany.ps1 | counts, spot-checked ids |
| Retired | | date marked dormant, DW site unbound |
