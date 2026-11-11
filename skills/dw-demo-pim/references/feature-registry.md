# feature-registry.md

> The PIM feature registry for a demo build: every feature a build applies, the product data it needs,
> when it applies, the only grounds on which a build may leave it out, and the proof that it is applied.
> Loaded from the PIM demo SKILL.md "Where to find things" table. Read it BEFORE
> [`canonical-setup-order.md`](canonical-setup-order.md): the setup order says how to build, this file says what
> the build must contain.

## Contents

- [Why a registry](#why-a-registry)
- [Step zero: the build file](#step-zero-the-build-file)
- [Attribute kinds](#attribute-kinds)
  - [Units on a measure](#units-on-a-measure)
- [Rulings](#rulings)
- [Model](#model)
- [Structure](#structure)
- [Assets](#assets)
- [Governance](#governance)
- [Publishing](#publishing)
- [Not registered](#not-registered)
- [Running the proofs](#running-the-proofs)

## Why a registry

A PIM demo that shows one data model and a column of text boxes looks like a spreadsheet. The features
below are what makes the product a PIM, and a build that skips one should be able to say why. So every
feature here either applies, or is ruled out on a ground this file lists. "Not needed for this demo" is
not a ground.

## Step zero: the build file

Before the first write, put `pim-build.json` in the solution folder. It is the product data registry of
this build, written from the brief and the customer context:

- `families[]`: the product families, each with the attribute category it will get (`name`, `category`).
  A family is a set of products that share an attribute set. A spec-heavy company has at least two.
- `attributes[]`: every attribute with `category`, `field` (the system name), `kind`, and for a measure
  `quantity` and `unit`. Add `required`, `perLanguage`, `perVariant` where they hold. An empty `category`
  is a global product field. Declare at least 12, with at least 3 measures and 3 choices.
- `rulings{}`: one entry per feature the build leaves out (below).
- `defaultLanguage`, `pimShop`, and on a local install `sql { server, database }` and `filesPath`.
- `productScope.exclude[]`: rows in the product table that are not catalogue products, each with an
  `idLike` prefix and a `reason`. For cart products an add-in writes, never for a catalogue product.

Then build in the order of `canonical-setup-order.md`, and keep the file true: an attribute added during
the build is added to the file.

## Attribute kinds

Pick the kind from what the value is, then the field type follows.

| Kind | The value is | Field type | Also |
|---|---|---|---|
| `measure` | a quantity with a unit: length, weight, volume, voltage, current, power, pressure, flow, temperature | Decimal | a unit group on the field with the unit as preset; the unit never goes in the label |
| `decimal` | a number with no unit: a ratio, a factor | Decimal | |
| `count` | a whole number of things: blades, poles, ports, months | Integer | |
| `choice` | one of a closed set | List, radio (2 to 3 options) or dropdown | at least 2 options |
| `multi-choice` | several of a closed set: certifications, compatible standards | List, checkbox list or multi-select | at least 2 options |
| `flag` | yes or no | Checkbox | |
| `date` | a date | Date or Date/time | |
| `text` | free short text | Text | |
| `code` | an identifier with a format: an HS code, a certificate number | Text | a validation pattern where the format is fixed |
| `long-text` | plain long text | Long text | |
| `rich-text` | formatted text | Editor | |
| `link` | a URL | Link | |
| `file` | one file that belongs to the value, not to the product as an asset | File | |
| `computed` | a formula or a concatenation of other fields | a field type with a Calculation or Concat provider | |

### Units on a measure

A measure is a Decimal field with a **unit group** (a field value conversion group) and a **preset unit**.
The editor then shows the unit beside the number, a language can show another unit of the same group, and
the value is stored in the group's base unit. Measured on DW 10.29 with MCP 0.6.5:

1. **Read what the host has.** `get_field_value_conversion_groups`, then `get_field_value_conversions` per
   group. A stock host ships weight, length and volume; power, current, voltage, pressure, flow and
   temperature are not there.
2. **A missing group has no MCP tool.** On a local install, insert one row in
   `EcomFieldValueConversionGroup` (name, system name) and one row per unit in `EcomFieldValueConversion`
   (parent group id, name, system name, factor to the base unit, sort order), then set the group's
   `FieldValueConversionGroupBaseUnitId` to the unit with factor 1, and recycle the host. Make the base
   unit the unit the source data is in, so the values load unconverted. Temperature gets a one-unit group:
   Fahrenheit is not a factor of Celsius. On a hosted install, the user creates the group on the field
   value conversion screen.
3. **Attach it over MCP.** `update_category_fields` (or `update_product_fields` for a global field) with
   `fieldValueConversionGroupId`, `fieldValueConversionPreset` (the unit id), `fieldValueConversionDecimals`
   and `fieldValueConversionDisplayRule: Fixed`. The same call sets `required`, `allowChangesAcrossLanguages`
   and `allowChangesAcrossVariants`.
4. **Per-language units** go on with `save_field_value_conversion_rules` after the group is attached.

An Integer field cannot take a unit, so a measure that happens to be whole (a power rating in hp, a
displacement in lb) is still a Decimal: create it as type 7 from the start. `create_category_fields` takes
`presentation` (`RadioButtonList`, `DropDownList`, `MultiSelectList`, `CheckBoxList`, `TagCloud`) and the
`options` for a list in the same call.

## Rulings

A feature is left out only by a ruling in `pim-build.json`:

```json
"rulings": {
  "assortments": { "applies": false, "rule": "open-catalogue",
                   "evidence": "One public price list; the brief names no dealer tiers or contract ranges." }
}
```

A ruling holds when it names a ground listed for that feature in the tables below, states the fact about
this catalogue that makes the ground hold, and is not contradicted by the data (a build that rules
translations out and then loads a second language has contradicted itself). A feature whose "May be left
out only when" cell says **never** has no ground. Write the rulings with the build file, before building:
a ruling written after a feature turned out to be hard is a skipped feature, not a ruling.

## Model

| Feature (`id`) | Product data it needs | Applies when | May be left out only when | Proof |
|---|---|---|---|---|
| **Data models per product family** (`data-models`) | The list of product families, each with its own attribute set (pim-build.json families[]). One attribute category and one data model per family, under a data-model folder in the DataStructure shop, with every product of the family related to its data model. | Always. A catalogue whose products do not all share one attribute set needs one data model per family; a spec-heavy company has at least two families. | **never** | - every declared family has a GroupType 2 data model on its category with at least one product, and at least two families are declared<br>- the DataStructure shop carries at least one data-model folder<br>- no active product sits outside every data model |
| **Data sets with inherited default values** (`data-sets`) | A sub-type inside a family whose products share fixed attribute values (a pack size, a series, a certification set), with those values named. | A family has a repeating sub-type whose products carry the same value for one or more attributes. | `no-shared-defaults`: no family has a sub-type whose products share a fixed attribute value | - at least one GroupType 3 data set exists<br>- at least one default value is stored on a data model or data set |
| **Typed fields: every attribute on the field type that fits its value** (`field-types`) | The product data registry (pim-build.json attributes[]): every attribute with its kind. measure and decimal are Decimal, count is Integer, choice and multi-choice are List, flag is Checkbox, date is Date, text and code are Text, long-text is Long text, rich-text is Editor, link is Link, file is File. | Always. A fixed set of choices is a list, a yes/no is a checkbox, a number is a number; text is for free text and codes only. | **never** | - every declared attribute is stored on a field type that fits its kind, and at least 12 attributes are declared<br>- the category fields use at least 7 distinct field types (the five text lengths count as one)<br>- at most 40 percent of the category fields are plain text<br>- every declared category attribute has a value on at least one product |
| **Units on measures** (`field-units`) | For every measure: the quantity (length, weight, volume, voltage, current, power, pressure, temperature, flow) and the unit the company states it in. One unit group per quantity with a base unit and the conversions the markets need; the unit set as the field's preset. | Always. A product with specifications has measures; a measure is a Decimal field with a unit group and a preset unit, never a unit in the label. | **never** | - every declared measure has a unit group and a preset unit on its field, and at least 3 measures are declared<br>- fields use at least 2 different unit groups (two quantities)<br>- every unit group in use has a base unit that is one of its own units<br>- no category field label carries a unit in brackets |
| **Unit shown per language** (`unit-rules-per-language`) | Which markets read metric and which read imperial, and the unit each language shows for each measure. | The build has languages for markets on different unit systems (for example en-US in inches and de-DE in millimetres). | `single-market`: the build has one language; `single-unit-system`: every language of the build belongs to a market on the same unit system | - at least one field shows a different unit for a language, and the unit resolves |
| **List fields with options, single and multi select** (`list-fields`) | For every choice attribute: the closed list of options with a stable value and a display name; which attributes allow more than one option. | Always. Materials, certifications, standards, colours, mounting types and connection types are closed vocabularies in every specification catalogue. | **never** | - every declared choice field has at least 2 options, and at least 3 choice attributes are declared<br>- at least one list field is a multi select (checkbox list or multi-select list)<br>- every value stored on a list field is one of the field's option values |
| **Required fields** (`field-rules`) | Per family, the attributes a product may not be saved without (pim-build.json attributes[].required). | Always. Every family has at least one attribute that identifies or legally qualifies the product. | **never** | - every attribute declared required is marked required on its field, and at least 2 are declared |
| **Validation pattern on formatted codes** (`field-validation`) | A text attribute with a fixed format (a part number scheme, a HS code, a certificate number) and its pattern. | The catalogue carries a code with a fixed format as a text field. | `no-formatted-codes`: no text attribute of the catalogue has a fixed format | - at least one field carries a validation pattern |
| **Fields that differ per language or per variant** (`field-scope`) | Which attributes are translated (marketing text, application notes) and which differ between variants of one product (size, colour, rating). | The build has more than one language or has variants. | `single-language-no-variants`: the build has one language and no variants | - every attribute declared per language or per variant allows that difference on its field, and at least 2 are declared |
| **Computed fields (calculation or concatenation)** (`computed-fields`) | A value derived from other fields: a dimension string, a converted figure, a generated title. | The catalogue shows a value that is a formula or a concatenation of other attributes. | `no-derived-values`: no attribute of the catalogue is derived from other attributes | - at least one field is built on a field type with a provider |
| **Field display groups** (`field-display-groups`) | How the specifications are grouped for a reader (Dimensions, Electrical, Certification), per family. | The build has a storefront or a feed that shows grouped specifications. | `no-consumer-of-groups`: the build has no storefront and no feed | - at least 2 named display groups each hold 2 or more fields<br>- every display group has a name (on the group, or a translation in the default language keyed by its id or its system name) |
| **Product numbers** (`identifiers`) | A unique item number per product and per variant. | Always. | **never** | - every active product and variant has a number (a master with variants is exempt: the platform blanks it)<br>- no product number is used twice |
| **GTIN / EAN on the standard field** (`gtin`) | The GTIN of every product traded through retail or marketplaces. | Products are sold through retail, marketplaces or any channel that identifies a product by barcode. | `no-barcode-channel`: no channel of the company identifies products by barcode (direct industrial sales only) | - at least 50 percent of the active products carry a GTIN on ProductEAN |
| **Manufacturers / brands** (`manufacturers`) | The brands in the catalogue, each with a name and a logo, and the brand of every product. | The catalogue carries more than one brand, or the brand is a search or filter dimension. | `single-own-brand`: every product is the company's own single brand and brand is not a filter | - at least 2 manufacturers exist<br>- at least 80 percent of the active products name a manufacturer that exists |
| **Units of measure on products** (`sales-units`) | The units a product is sold in (each, box, pallet, metre) and the quantity per unit. | A product is sold in more than one unit, or in a unit other than a piece. | `pieces-only`: every product is sold by the piece and in no other unit | - at least 2 units exist<br>- at least 2 product unit rows exist (a product with its units and quantities) |

## Structure

| Feature (`id`) | Product data it needs | Applies when | May be left out only when | Proof |
|---|---|---|---|---|
| **Variants** (`variants`) | Products that exist in several orderable versions of one thing, the axis or axes that tell them apart (size, colour, voltage, length), the options on each axis and the item number of each combination. | A product is ordered in versions that differ only by one or more options. | `no-orderable-options`: no product of the catalogue exists in versions that differ only by an option | - at least one variant group has 2 or more options<br>- at least 2 products have variant rows<br>- no variant row was left with a NULL active flag<br>- every variant row has its own number |
| **Bundles and parts lists (BOM)** (`bom`) | Kits, assemblies or sets, each with its component products and quantities. | The company sells a kit, a set or an assembly made of other catalogue products, or publishes a parts list per product. | `no-kits-or-assemblies`: no product is sold as a set of other catalogue products and no parts list is published | - at least one product of type BOM has 2 or more component lines<br>- every BOM line names a component product or a group that exists |
| **Product relations (accessories, spare parts, replacements)** (`product-relations`) | Per product: its accessories, its spare parts or consumables, and its successor when it is replaced; one relation group per kind. | Products have accessories, spare parts, consumables or successors in the same catalogue. | `no-related-products`: no product of the catalogue is an accessory, spare part, consumable or successor of another | - at least 2 relation groups exist (two kinds of relation)<br>- at least 10 relations exist<br>- every relation names two products and a relation group that exist |
| **Dynamic relations with amounts (materials, packaging, ingredients)** (`dynamic-relations`) | Per product: the materials, packaging components or ingredients it is made of, each with an amount. | The company must state what a product is made of or packed in with amounts (material declarations, packaging reporting, a product passport). | `no-composition-data`: the company does not publish or report the composition or packaging of its products | - at least one dynamic relation group exists<br>- at least 5 dynamic relations exist |

## Assets

| Feature (`id`) | Product data it needs | Applies when | May be left out only when | Proof |
|---|---|---|---|---|
| **Product images with a default** (`images`) | At least one image per product, one of them marked as the default. | Always. | **never** | - at least 90 percent of the active products have an image<br>- no product has images and no default image |
| **Documents in their own asset categories** (`documents`) | Per product: datasheet, manual or installation guide, certificate or declaration; one asset category per document kind with its file-type filter. | Always. A product with specifications has at least a datasheet. | **never** | - at least 2 asset categories that accept pdf each hold at least one asset<br>- at least 10 products carry a document<br>- every asset category in use has a name in the default language |

## Governance

| Feature (`id`) | Product data it needs | Applies when | May be left out only when | Proof |
|---|---|---|---|---|
| **Completeness rules per family** (`completeness-rules`) | Per family, the fields a product needs before it may be published. | Always. | **never** | - at least 2 completeness rules each list 3 or more fields<br>- every data model that holds products has a completeness rule assigned |
| **Product workflow with states, transitions and notifications** (`workflow`) | The enrichment steps a product passes (for example Draft, Technical review, Approved), who is told at each step, and where each seeded product stands. | More than one person or role works on product data before it is published. | `single-editor`: one person owns all product data and nothing is reviewed before publication | - one workflow has at least 3 states<br>- at least 3 transitions connect states that exist<br>- the workflow is attached to at least one group<br>- products stand in at least 2 different states<br>- at least one state sends a notification that has recipients |
| **Saved product queries (worklists)** (`product-queries`) | The questions the team asks of the catalogue: what is incomplete per family, what waits for review, what is in which channel, what lacks a translation. | Always. | **never** | - at least 5 saved product queries exist in the shared query folder |
| **PIM dashboard with query-backed widgets** (`dashboards`) | The numbers the product manager watches: incomplete per family, waiting for review, missing translation, per channel. | Always. | **never** | - at least one Products dashboard has 4 or more widgets<br>- every widget on a Products dashboard that names a query names one that exists |
| **Dynamic workspaces** (`workspaces`) | The slices the team works in: by family, by brand, by a specification, by what is incomplete. | Always (the PIM licence feature carries them). | **never** | - at least 2 workspaces each have a level<br>- no workspace was saved with zero levels<br>- at least one workspace level shows completeness |
| **PIM email notifications on a query** (`email-notifications`) | Who is mailed when a worklist has rows (the enricher when products are incomplete, the reviewer when products wait). | More than one person or role works on product data. | `single-editor`: one person owns all product data and nothing is reviewed before publication | - at least one PIM notification has a recipient |
| **Field permissions per role** (`field-permissions`) | The roles in the product team and the fields each may read or edit (pricing fields for pricing, technical fields for engineering). | More than one role works on product data and not every role may edit every field. | `single-editor`: one person owns all product data and nothing is reviewed before publication; `all-roles-edit-all-fields`: every role of the product team may edit every field | - at least 2 field permissions are stored |
| **Product edit screen layout and list presets** (`screen-layouts`) | The tabs and field groups an editor needs on the product screen, and the columns each role wants in the product list. | A family carries more attributes than one tab shows readably. | `under-25-fields-per-family`: no family carries more than 25 attributes | - at least one active screen layout has a tab<br>- at least one list preset has 3 or more columns |

## Publishing

| Feature (`id`) | Product data it needs | Applies when | May be left out only when | Proof |
|---|---|---|---|---|
| **Channels with their own group tree** (`channels`) | The places product data goes (webshop, marketplace, dealer portal, print, a partner), and which products go to each. | Always. Product data that goes nowhere is not a PIM story. | **never** | - at least one channel has a group that holds products<br>- no group is shared between two shops or channels<br>- no channel is empty |
| **Feeds** (`feeds`) | Per outgoing feed: the receiver, the format (JSON, XML, template), the products (a query, a channel or groups), the language and the fields. | Always. A channel that is not a Dynamicweb storefront receives its data as a feed. | **never** | - at least one feed has a provider<br>- every feed has a provider, a language and a product source (query, channel, shop or groups)<br>- every template feed states a content type |
| **Assortments** (`assortments`) | Which customers or customer groups may see which part of the catalogue, AND the range an anonymous visitor may see. One active assortment switches access control on for every visitor of every shop: a visitor with no assortment sees no product. So the anonymous assortment that covers the public range is created, related and built first, and only then is anything activated. | Not every buyer may see every product (dealer tiers, regional ranges, contract ranges). | `open-catalogue`: every buyer may see every published product | - at least one active assortment has a group, product or shop relation<br>- at least one assortment is granted to a user or group that exists<br>- the assortments were built (assortment items exist)<br>- an active, built assortment is open to anonymous visitors, so the public range did not go blank when assortments were switched on |
| **Product assignment rules (auto-assign to groups)** (`auto-assign`) | The rule that places a product in a channel group: a query, or an attribute value per group. | Channel groups are filled by an attribute or a query rather than by hand. | `under-250-products`: the catalogue is small enough to place by hand | - at least one active assignment rule is a query rule or has a mapping |
| **Translations of products, field labels and list options** (`languages`) | The languages of the markets served; translated name and description per product; translated field labels and list option names. | The company sells in more than one language. | `single-market`: the company sells in one language | - at least 20 products have a row in a second language<br>- at least 80 percent of the translated rows carry a long description that differs from the default language<br>- field labels are translated into a language that has product rows<br>- list option names are translated into a language that has product rows |
| **Data Integration activity for the product load** (`integration`) | The source the product rows come from (an ERP export, a supplier sheet) and its mapping to product fields. | The catalogue is loaded from a source file or system rather than typed. | `under-250-products`: the catalogue is small enough to seed without an import | - at least one Data Integration activity is stored |

## Not registered

These are PIM features, and a build may show them, but none has build-time state a proof can read, or
applying them needs something a demo host does not have:

- Grid edit, bulk update, Excel export and import: tools. Show them live.
- Review changes and comments: records the demo creates when it is given.
- Range and Matrix fields: behind feature flags, and Range is half-implemented
  ([`dw-pim-modelling`](../../dw-pim-modelling/references/structural-model.md)). Model a range as two measures.
- AI text and machine translation: need a provider key on the host.
- Image patterns and auto check-in: another way to attach assets, not a further feature.
- Stock, prices, VAT groups: commerce data. A PIM build sets them only as far as a channel needs them.

## Running the proofs

Every proof in the tables is one measured number or one list of offenders, never a judgement. Each reads
from the tables the foundational skills name: fields and their flags on the category-field and
product-field tables, unit groups on the field value conversion tables, options on the field option table,
and so on. On a local install they are read-only `SQL` (rung 4 of
[`access-surfaces.md`](access-surfaces.md): reads and census queries); a build host may carry a runner that
takes `pim-build.json` and returns PASS, FAIL or NOT-APPLICABLE per feature. On a hosted install, read the
same facts with the MCP reads (`get_product_category_fields` for labels, `get_field_value_conversion_groups`,
`get_manufacturers`, `get_assortments`, `get_feeds`, `get_dashboards`, `get_workflow_states`,
`get_variant_groups`, `get_product_relation_groups`) and say for each proof which read answered it.

Report per feature: PASS, FAIL with the measured value, or NOT-APPLICABLE with the ground and the
evidence. A build is done when no feature fails.
