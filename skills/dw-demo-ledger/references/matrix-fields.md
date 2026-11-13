# Matrix fields on [dw 10.29.8]

## Contents

- [Declared source values](#declared-source-values)
- [Six checks](#six-checks)
- [Building a matrix](#building-a-matrix)
- [Release evidence and handoff](#release-evidence-and-handoff)

The release scan must finish and preserve its raw output before this feature is
reviewed. No matrix keyword belongs in the scanner. `pim.matrix-fields` is absent
from [dw 10.28.15]. Its [dw 10.29.8] declaration requires the observed boolean feature
`Dynamicweb.Ecommerce.Products.MatrixFieldTypeFeature`.

`FeaturesAll` is an authenticated GET query. Complete, typed results populate
capability facts. Off means DISABLED; an unavailable or ambiguous observation means
UNVERIFIED. The runner never toggles the flag. MCP has no equivalent feature flag
read in the observed configuration, so this read uses the Admin API.

## Declared source values

Put this object under `expected.matrix` in the build declaration, alongside the
normal lock and requested functions. Replace these synthetic identifiers and
values with the approved source data before running. An empty table cannot pass.

```json
{
  "categoryId": "Matrix_nutrition",
  "columns": [
    {"id": "nutrient", "type": "Text"},
    {"id": "per_100g", "type": "Double"},
    {"id": "unit", "type": "Text"}
  ],
  "subjects": [{
    "productId": "EXAMPLE_PRODUCT",
    "variantId": "",
    "languageId": "LANG1",
    "ownerCategoryId": "food",
    "ownerFieldId": "nutrition",
    "rows": [
      {"sortOrder": 0, "cells": {"nutrient": "Salt", "per_100g": 0.2, "unit": "g"}},
      {"sortOrder": 1, "cells": {"nutrient": "Energy", "per_100g": 20, "unit": "kcal"}}
    ]
  }]
}
```

One to six distinct columns, explicit product/variant/language identities and all
cells are required. Rows are zero based and contiguous. Values must be nonempty
scalars; null and omitted values require a future declared sparse-cell contract.
Text is compared exactly. Integer and Double values are compared numerically using
invariant culture, including zero; the stored text must be a sign, digits and a decimal
point (padding or an exponent is another stored representation and fails). A FAIL names
the cell with its observed and expected value. Every subject must have its own source rows.
This contract checks a matrix owned by an attribute category field; it does not
claim support for global custom fields without a declared owning category.

## Six checks

| Check suffix | Read and proof | Red control |
|---|---|---|
| `field-type` | MCP `get_field_types`, `dynamicwebAlias == Matrix`; local SQL fallback resolves FieldTypeDW without assuming the Matrix type id | Missing Matrix alias fails |
| `flag-on` | Authenticated complete FeaturesAll observation | False fails the assertion; the function requirement reports DISABLED |
| `columns` | Local SQL reads CategoryType 3 and exact column ids/types, and each declared owner field's type and `FieldMatrixAttributeGroupId` | Wrong category or column type, an owner field that is not Matrix or is linked to another matrix category fails |
| `parent-marker` | One marker per product/variant/language and owning field: row zero, NULL value, reference to the matrix category; every marker that references the category, counted per product/variant/language and owner field | Missing or altered marker, an undeclared marker or one in another owner field fails |
| `cells` | Exact rows times columns, scoped by matrix category and product/variant/language; no missing, extra, duplicate or changed cells; every cell of the category counted per product/variant/language | One changed source cell, rows on an undeclared product or language, a padded or exponent number fails |
| `negative-control` | The same cell comparator first accepts the observed data, then rejects an in-memory altered copy | Already incorrect input fails; the target is never changed |

Matrix columns allow platform type ids 1, 6, 7, 8, 10, 11, 12, 13 and 15 in the
[dw 10.29.8] MatrixHelper metadata implementation. Aliases are Text, Integer, Double,
Link and List. Lists require DropDownList presentation (2). The Matrix field type
itself is always looked up by alias.

Cell sort zero and parent sort zero are distinct because their categories differ.
The native SaveMatrixValues implementation indexes cells from zero. Tests compare
the category as well as field and row. All SQL is a single SELECT per read, with
escaped literal keys and integrated authentication on an explicit local server.

MCP remains first for the supported field-type read. The current category field and
product DTOs have not established complete matrix cell, row and parent evidence;
their bindings stay planned. Those stored-integrity checks require local SQL.
No fallback silently upgrades an incomplete MCP observation to a pass.

## Building a matrix

Measured on [dw 10.29.8] in the release A/B build (food-ingredient catalogue, 2026-11-12):

- Toggle the flag through the Management API command `FeatureManagementToggle` with body
  `{"FeatureTypeName": "<feature type name>"}`. `FeatureManagementToggleCommand` answers
  "Unknown command".
- Save the owner field with `ProductFieldSave` and the Matrix type looked up by alias (id 18 on
  that host; never hard-code it). The platform then creates the matrix category itself as
  `Matrix_<fieldSystemName>` (name "Matrix column configuration", CategoryType 3) and ignores a
  requested `MatrixAttributeGroupId`. Do not create your own matrix category; add the columns to
  the one the platform made and declare that id as `categoryId`.
- List columns need DropDownList presentation (2).
- No MCP tool in the 0.6.x add-in writes matrix cells. The build wrote the stored shape directly:
  the parent marker on the owner field, cells in the matrix category, rows from 0. `ProductById`
  then returned the field as a matrix value.

## Release evidence and handoff

The snapshot's `delta.json` and `delta-review.json` link the preserved raw scan
digest, new feature subclass, public matrix types, CategoryType enum member,
three schema columns, key membership and release work items. Package bytes were
read as metadata; target assemblies were never loaded or executed.

Create a fresh lock with the exact producer commit, manifest, snapshot digest and
six check ids. A former lock cannot silently acquire these checks. Keep the source
value declaration, flag-off report, flag-on report and changed-cell report together.
The in-memory control proves the comparator. A demo's deliberate changed-cell run
is separate evidence and must be performed by its authorised build session.

The 10.30.6 snapshot carries the six checks unchanged. The 10.30 line adds inheritance from
MASTER to the default language and shared or language-specific values per matrix column. The cells
check reads stored rows for the language each subject declares, so a value that is inherited or
shared from another language is not a stored cell in that language: declare the language that
stores it. On a matrix host after the upgrade to [dw 10.30.6] the cells were still stored per
product and language, and no matrix column or key changed (`10.30.6/delta.json` limitations).

Read-only implementation: [Pim.Matrix.ps1](../scripts/Pim.Matrix.ps1).
Controls: [Matrix.Tests.ps1](../scripts/tests/Matrix.Tests.ps1).
Official references: [MatrixHelper API](https://doc.dynamicweb.dev/api/Dynamicweb.Ecommerce.Products.MatrixHelper.html),
[release notes](https://doc.dynamicweb.dev/documentation/fundamentals/dw10release/releasenotes/changelog.html).
