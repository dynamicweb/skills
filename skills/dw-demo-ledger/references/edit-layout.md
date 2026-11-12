# Product edit layout and field placement

Two Truvio Commerce (powered by Dynamicweb) PIM functions judge how an editor meets the product data: `pim.screen-layouts` (the product edit screen) and `pim.field-placement` (where a family's attributes are stored). Their checks use the handlers `pim-edit-layout` and `pim-field-placement` in [Pim.Layout.ps1](../scripts/Pim.Layout.ps1). Each reads its tables once per run; every rule is a pure function over that read, so each judgement has a red control without a database ([Layout.Tests.ps1](../scripts/tests/Layout.Tests.ps1), [Placement.Tests.ps1](../scripts/tests/Placement.Tests.ps1)). Limits and banned names are binding `arguments` in the probe file, never code.

## Decide the tabs before building

Without a layout, a family's attributes sit on the stock Categories tab, below every other family's, and global custom fields on a tab called Custom. One active layout applies to the product edit screen for every user, so tabs are a property of the solution; a role's own view is a list preset.

1. **One tab per family, named after the thing.** A tab that carries only one family's category fields is shown only on that family's products. Name it with the editor's word for the product (`Centrifugal pump`, `Valve`), never the mechanism (`Categories`, `Custom`, `PumpAttrs`).
2. **Keep a family tab pure.** No standard field, no other family's field and no catch-all group on it; any of those makes it show on every product.
3. **Divide the shared fields one way, and say which.** State `role`, `task`, `lifecycle` or `source` in the build's `editLayout`, with a reason. The checks do not judge the choice, only that it was stated and that the layout matches it.
4. **At most 5 tabs on any one product**: the shared tabs plus that family's own.
5. **Groups an editor can scan**: at most 12 editors per group and 30 per tab; every group name used once.
6. **Exactly one catch-all group**, on a shared tab. It is the one group that may be called `Other fields`.

A category with fields that is not a declared family (a product passport, a block several families carry) is a shared category: its fields go on a shared tab or a tab of their own, and that tab counts as shared for every family.

## `editLayout` in the build

| Key | Required | Value |
|---|---|---|
| `division` | yes | `role`, `task`, `lifecycle` or `source` |
| `reason` | yes | why the shared fields are divided that way |
| `tabs[]` | no | the layout's tabs, any order |
| `tabs[].name` | yes | the tab name as stored |
| `tabs[].for` | yes | `shared`, or the category id whose fields the tab carries |
| `tabs[].owner` | no | the role or source system that maintains it; recorded, not checked |

A build with no `editLayout` fails `division-stated`. An unknown division, a blank reason or a tab without name or `for` fails the build schema. A tab declared twice is an offender of `division-stated`.

## Checks

`pim-edit-layout` takes `arguments.aspect` and the aspect's limits. Every check is an offenders assertion.

| Check | Aspect | Measures | Limit |
|---|---|---|---|
| `product-edit-layout` | `screen-type` | active layouts with a tab for `Dynamicweb.Products.UI.Screens.ProductEditScreen`; a short or misspelt type is stored and never applied | exactly 1 |
| `editors-resolve` | `editors-resolve` | `CategoryFields\|ProductCategory\|<category>\|<field>` editors with no stored field | 0, at least 1 placed |
| `family-tabs` | `family-tabs` | family fields on no tab, tabs mixing families, family tabs carrying anything else | 0 |
| `tabs-per-product` | `tabs-per-family` | shared tabs plus the family's own tabs | `maxTabs` 5 |
| `scannable` | `scannable` | editors per group and per tab | `maxEditorsPerGroup` 12, `maxEditorsPerTab` 30 |
| `editor-words` | `names` | blank names, `bannedNames`, a category id, `bannedPatterns` | 0 |
| `one-catch-all` | `catch-all` | catch-all groups | exactly 1 |
| `unique-group-names` | `unique-group-names` | group names used more than once, case-insensitive | 0 |
| `division-stated` | `division` | `editLayout` present; declared tabs against layout tabs both ways; shared tabs carry no family field; a category tab carries that category only | 0 |

Standard fields, global custom fields and completeness rules have editor names the platform defines; `editors-resolve` counts them and does not judge them. When no active layout names the product edit screen, every other layout check FAILs with "nothing was measured"; `division-stated` reads the layout only when `editLayout` declares tabs.

`pim-field-placement` takes `arguments.minSharePct` (50): every custom global product field must carry a value on at least that share of the in-scope products (master rows in `defaultLanguage`, `productScope` exclusions applied). Empty text, NULL and 0 are no value. A checkbox and a computed field are counted and not judged. Declaring a field global in `attributes[]` does not exempt it. A column that cannot be read is an offender. A build with no `defaultLanguage` is UNVERIFIED.

## Grounds

`pim.screen-layouts` is ruled out only by `one-attribute-family`: at most one data model carries fields and it has at most 25. `pim.field-placement` is ruled out only by `single-family-catalogue`: at most one data model carries fields. A ruling on the retired ground `under-25-fields-per-family` is invalid.

## Known limits

- A tab named exactly like a category id is an offender, so a family whose category id is a plain word cannot have a tab of that name.
- A shared-category tab counts for every family in `tabs-per-product`, even where only some families carry that category.
- A legitimate 0 in a number field reads as no value in the share.
- Global custom field editors on a layout are not judged; their editor names are not measured.
- Admin API and MCP bindings are planned: no measured read returns the layout tree or a complete per-field fill count.
