# Structural inventory — every entity, its origin, its keys

## Contents

- [Goal](#goal)
- [Run the pull](#run-the-pull)
- [Origin classification — standard, ISV, custom, unknown](#origin-classification--standard-isv-custom-unknown)
- [Company scope and keys](#company-scope-and-keys)
- [Extension fields on standard entities](#extension-fields-on-standard-entities)
- [No-code custom fields](#no-code-custom-fields)
- [Baseline diff](#baseline-diff)
- [What the inventory cannot tell you](#what-the-inventory-cannot-tell-you)

## Goal

A normalized `model.odata.json` + `entities.csv` naming every entity the environment exposes, who put it there (Microsoft, an ISV, the customer), whether it is company-scoped, its keys, and the extended data type behind every property. This is the input to key centrality and the skeleton of the brief's origin map and extension inventory.

## Run the pull

```powershell
& <skill>\assets\scripts\Get-FoToken.ps1 -TenantId <guid> -ClientId <guid> -EnvironmentUrl https://<env>.operations.dynamics.com
& <skill>\assets\scripts\Export-FoMetadata.ps1 -OutDir <discovery-dir> -IncludeEnums `
    -PrefixMap @{ 'XYZ' = 'isv:<vendor>'; 'ABC' = 'custom' } -LabelFileMap @{ '<InHouseLabels>' = 'custom' }
```

Outputs under `<discovery-dir>/`: `metadata/installed-modules.json`, `metadata/data-entities.json`, `metadata/public-entities.json`, (`metadata/public-enumerations.json`, `metadata/metadata.edmx`), `model.odata.json`, `entities.csv`. The console line reports how many label files are still `unknown` — that number goes to zero through the ERP owner's answers, not through guessing.

## Origin classification — standard, ISV, custom, unknown

Three signals, applied in this order by the exporter:

1. **Installed modules** — `POST /data/SystemNotifications/Microsoft.Dynamics.DataEntities.GetInstalledModules` returns `Name | Version | Module | Publisher | DisplayName` lines. Every publisher other than Microsoft is an ISV or the customer's partner; the module name is usually also the label-file name and the object prefix. This action is undocumented and may be role-gated — when it fails, get the list from *? > About > Show installed models* and pass the result through `-PrefixMap` / `-LabelFileMap`.
2. **Label file of `LabelId`** — `@SYS…`, `@SYP…` and Microsoft's module label files → standard; a label file matching an ISV module → that ISV; anything else → `unknown` and listed in `labelFiles[]` with its entity count. Microsoft requires ISVs to ship their own label files, which makes this the most reliable external classifier.
3. **Name prefix** — `-PrefixMap` for known prefixes; a leading 2–5 character uppercase run before a capitalised word (`XYZUnitTable`) is reported as an unknown prefix. Standard OData names have their AOT prefixes stripped (`EcoResReleasedProductEntity` → `ReleasedProduct`), so a prefix that survives into the public name is itself a signal.

Fields get the same treatment individually (`fields[].origin`) — a standard entity with three fields labelled from an ISV file is an *extended* standard entity, which is exactly what the extension inventory needs.

## Company scope and keys

- `saveDataPerCompany` = the entity has a `dataAreaId` property. Company-scoped entities are counted per legal entity in the census; global ones (parties, products' shared master, workers, users) once.
- `keys[]` = properties with `IsKey`. Composite keys that include `dataAreaId` are normal. An entity whose key is only a surrogate (`RecId`-typed) has no natural key — flag it; stage 1 staging will need `RecId` as the delta key.
- `fields[].labelId` = the property's `LabelId`. The Metadata service exposes **no extended data types** (`TypeName` is only the `Edm.*` primitive or the enum type), so the label is the semantic grouping key on F&O models: properties sharing `@SYS7149` ("Customer account") across entities are the same concept whatever their names. `fields[].edt` is populated by the XPO converter only.
- `fields[].enum` = enum type name for enum-typed properties (from `TypeName`); enums are classifications, never keys.
- `relations[]` = navigation properties with their referential constraints — the join edges for centrality and the map of which entities are reachable from which.

## Extension fields on standard entities

Microsoft's naming rules forbid prefixes and underscores in standard entity fields, so a property on a standard entity that carries a vendor prefix, an underscore, or a non-Microsoft label file is an extension field. `entities.csv` column `customFields` counts them per entity; the extension inventory in the brief lists them with the census fill rate — an extension field that is never populated is a dead extension, and the customer should say so.

Extension *elements* (`Table.Vendor_Extension`, `_Extension` classes) never appear in OData; the field is all you see. Which model owns the field is answered by the installed-modules list, not by the metadata.

## No-code custom fields

Fields created through *Personalize > Insert > Field > Create new field* appear on the entity contract only after an admin enables them per entity on the *Custom fields* page (*Entities* section). Consequences:

- A custom field visible in the UI but absent from `model.odata.json` is either not entity-enabled or on a table with no entity — ask the admin to enable it, then re-pull.
- No entity lists the custom-field catalog; the `CustomFields` collection is the billing-code feature, unrelated. `CustomFieldPicklistValues` exposes picklist values only. The *Custom fields* form is reachable via the ERP MCP `form_*` tools when API access is not enough.
- Hard limits (20 per table, main/worksheet/reference/parameter table groups only, not extended tables) bound how much business model can hide here.

## Baseline diff

For a precise "what was added on top of standard" answer, diff `metadata/metadata.edmx` (or `public-entities.json`) against the same pull from a clean environment of the **same application version** (`GetApplicationVersion`). Entities and properties present only in the examined environment are extensions; entities missing there are configuration-key disabled. Keep baselines per version in a shared folder (`baselines\fo\<version>\`) so the next discovery on that version reuses them.

## What the inventory cannot tell you

- **Root table names** — the Metadata service exposes the entity contract only. Entity → table mapping comes from the technical-reference *Data entities* report or from the AOT.
- **Configuration keys / license state** — no entity exists; `ConfigurationEnabled` on entities and properties is the only API-side signal, and the *Config keys* report is the authoritative one.
- **Which fields are populated** — that is the census ([population-census.md](population-census.md)). Structure without population over-counts by an order of magnitude on any real tenant.
