# Excel Contract And Mapping

## Workbook contract
Accept flexible workbook names. Derive the default shop name from the last non-empty meaningful filename token.

- Split filename tokens on `_`, `-`, and spaces.
- Ignore `pim`, `configuration`, and `automation` when deriving the project token.
- If the user provides an explicit shop name, use that instead.

Examples:

- `PIM_Configuration_Automation_Dunlop_.xlsx` -> `Dunlop`
- `PIM-Configuration-Dunlop.xlsx` -> `Dunlop`
- `PIM_Configuration_Automation__Dunlop__2026.xlsx` -> `2026`
- `PIM Configuration - Dunlop - Final.xlsx` -> `Final`
- `PIM_Configuration_Automation_Dunlop` -> `Dunlop`

## Required sheets and columns
Read only:

### `ProductGroups`
- `GroupName`
- `GroupId`
- `ParentGroupId`

### `ProductAttributes`
- `Attribute name`
- `Field Type`
- `Example enrichment`
- `Attribute Type`
- `Listbox Options`
- `Maintained`
- `PIM Groups`
- `Front-end filter`

Ignore all other sheets, including `Translations`.

## Mapping rules
- `Field Type = GF` maps to global product fields.
- `Field Type = CF` maps to category fields via `PIM Groups`.
- Blank `Field Type` is allowed and should be ignored for generation but retained in validation output.
- Use `GroupName` exactly as the group display name after trimming leading and trailing whitespace.
- Do not append `GroupId` or any other suffix or prefix to group display names.
- First-level parent group names must be `GroupName` only from `ProductGroups.GroupName`.
- Second-level DataModel names must be the child `GroupName` only from `ProductGroups.GroupName`.
- Category display names for second-level items must be `<ParentGroupName>|<ChildGroupName>`.
- Category-specific completion-rule names must be `<ParentGroupName>|<ChildGroupName>`.
- `GroupId` is the second-level ProductGroup or DataModel id from `ProductGroups`.
- `CategoryId` is the category attached to that DataModel.
- Verify physical CF fields with `ProductCategory|<CategoryId>|<FieldId>`.
- Serialize CF completion-rule fields with `ProductCategory|<CategoryId>|<AttributeSystemName>`.
- Maintain a deterministic one-to-one `GroupId -> CategoryId` mapping before CF or completion-rule processing.

Example for parent `Tennis` and child `Tennis Racket`:

- Group/DataModel name: `Tennis Racket`
- Category group name: `Tennis|Tennis Racket`
- Completion rule name: `Tennis|Tennis Racket`

## Attribute metadata rules
- Treat `Maintained` case-insensitively.
- `ERP` or `DW` must become the description value `ERP` or `DW` exactly.
- `Other` or blank means no maintained metadata.
- `Maintained` controls metadata only. It must not be used to omit, skip, filter, or defer any attribute.
- If `Maintained` resolves to `ERP` or `Source ERP`, mark the field as read only.
- If `Maintained` resolves to `DW`, `Dynamicweb`, `Other`, or blank, do not infer read-only from `Maintained`.
- `Attribute Type = List` means list field plus options.
- For both GF and CF list fields, persist list-option `Name` exactly as in Excel and persist list-option `Value` as the normalized machine key.
- The direction is strict:
  - `Name = Excel label`
  - `Value = NormalizeMachineId(ExcelLabel)`
- Sort listbox options deterministically before write.
- If labels are numeric-like, sort from lowest to highest with numeric comparison rather than lexical string comparison.
- If both single numeric values and numeric intervals are present:
  - sort single values first from lowest to highest
  - sort interval values after the single values by interval start, then interval end
- If labels are primarily text-based, sort alphabetically `A-Z` by display label.
- If labels contain units or symbols, preserve the display label exactly and use only the extracted numeric meaning for ordering.
- Do not preserve workbook encounter order unless the user explicitly requests source-order persistence.
- The inverse payload direction is invalid for this skill:
  - `Name = normalized key`
  - `Value = Excel label`
- If a tool example, previous implementation, or backend example shows the inverse direction, do not follow that example for this skill.
- Never swap `Name` and `Value`.
- `Attribute Type = Kommatal` means numeric.
- `Attribute Type = Tekst (255)` means short text.
- `Attribute Type = Lang tekst` means long text or editor text.
- Apply language inheritance by resolved field type:
  - `listbox` and `decimal` must use `allowChangesAcrossLanguages = true`
  - `editor` and `text255` must use `allowChangesAcrossLanguages = false`
  - other supported field types keep the skill baseline unless the user explicitly overrides it
- Keep `allowChangesAcrossVariants = false` unless the user explicitly overrides it.
- Default list presentation is `MultiSelectList`.
- This is a strict cross-scope rule, not a best-effort default.
- Every listbox field must use `MultiSelectList`, including:
  - GF fields persisted as `productFields`
  - CF fields persisted as `categoryFields`
- Do not interpret this rule as CF-only.
- Ignore `Front-end filter` operationally.
- Only attributes may receive descriptions.

## Source-material reading order
Use this order when additional project files are present:

1. Workbook contract
2. `Step1_ExcelDataPreparationGuide_CustomerName.docx`, if the user or repository provides it
3. `PIMAutomationProcess_EN.docx`, if the user or repository provides it
4. `HowToImplement.docx`, if the user or repository provides it
5. `1. Overview.sql`
6. `2. CreateTables.sql`
7. `3, CreateViews.sql`
8. `4. CleanupScripts.sql`
9. `5. Facets.sql`
10. `AdvancedCleanupScript.sql`
11. `0 Raw data Import to tables.xml`
12. `1 - Global fields.xml`
13. `2 - Category fields .xml`
14. `3 - Listbox options.xml`
15. `4 - Product Groups.xml`
16. `5 Import Products (Covetrus).xml`
17. `5 Import Products (Dunlop).xml`
18. Optional scope docs such as `Workshop Questions.docx` and `PIM Automation Process Customer Specific.docx`
