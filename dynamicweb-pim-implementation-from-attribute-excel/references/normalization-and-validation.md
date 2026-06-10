# Normalization And Validation

## Shared normalization
Use one shared normalization function named `NormalizeMachineId`.

Apply it to:

- GF and CF field system names
- List option value keys
- Generated ids from attribute names
- Product category ids when they participate in technical system names or completion-rule paths
- Completion-rule attribute tokens in `ProductCategory|<CategoryId>|<AttributeSystemName>`

Keep labels and display names exactly as entered in Excel. Normalize only machine identifiers.

## Normalization algorithm
Apply exactly:

1. Trim whitespace.
2. Lowercase.
3. Transliterate with this exact table:
   - `Ã¦`,`Ã†` -> `ae`
   - `Ã¸`,`Ã˜` -> `oe`
   - `Ã¥`,`Ã…` -> `aa`
   - `Ã¤`,`Ã„` -> `ae`
   - `Ã¶`,`Ã–` -> `oe`
   - `Ã¼`,`Ãœ` -> `ue`
   - `ÃŸ`,`áºž` -> `ss`
4. Remove remaining Latin diacritics using Unicode decomposition and removal of combining marks.
5. Replace any character outside `[a-z0-9_]` with `_`.
6. Collapse repeated underscores.
7. Do not trim leading or trailing underscores.
8. Cap at 255 characters.
9. Hard-fail if the result is empty.

## Collision policy
- For GF and CF field ids and generated attribute ids: hard-fail if different source values normalize to the same machine id inside the same scope.
- For list options within one field: keep the first occurrence per normalized key, drop later duplicates, and report the dropped values.
- For completion-rule CF tokens: only allow tokens whose `<AttributeSystemName>` matches an existing normalized category-field id for that `CategoryId`; otherwise hard-fail.

## Preflight QA gate
Run a preflight QA gate on the fully assembled intended payload before any write.

- The run must assemble the entire workbook as one complete payload before the first write.
- Hard-fail if the run is assembled as fieldwise, entitywise, or other partial writes instead of one complete payload.
- Hard-fail if any expected technical id contains characters outside `[a-z0-9_]`.

Apply the technical-id character gate to:

- Product field system names
- Product category field system names
- Product category ids when they participate in `ProductCategory|<CategoryId>|<FieldId>` or `ProductCategory|<CategoryId>|<AttributeSystemName>`
- Listbox option values
- Completion-rule field tokens for category fields

Do not apply the technical-id character gate to human-readable display names such as:

- Shop names
- Group names
- DataModel names
- Category display names

## Hard-fail rules
- Missing required sheet
- Missing required column
- Invalid or duplicate `GroupId`
- `ParentGroupId` referencing an unknown `GroupId`
- Invalid `Field Type` outside `GF`, `CF`, or blank
- Invalid `Attribute Type`
- `List` without options
- Modified or sanitized list option `Name`
- Non-normalized list option `Value`
- Unknown `GroupId` in `PIM Groups`
- Empty normalized machine id
- Technical id containing characters outside `[a-z0-9_]`
- Normalization collision in the same scope
- Missing or ambiguous `GroupId -> CategoryId` mapping
- Group display name not matching `ProductGroups.GroupName`
- Second-level DataModel name not matching child `ProductGroups.GroupName`
- Category display name not matching `<ParentGroupName>|<ChildGroupName>`
- Category-specific completion-rule name not matching `<ParentGroupName>|<ChildGroupName>`
- Duplicate CF list options persisted for the same `(FieldId, OptionValueKey)`
- Missing expected physical category fields after provisioning
- Missing or incorrect completion-rule assignment on target second-level groups or DataModels
- Category completion-rule fields not serialized as `ProductCategory|<CategoryId>|<AttributeSystemName>`
- Payload assembled as partial writes instead of one complete workbook payload

## Auto-fix rules
- Trim cell whitespace
- Normalize spaces around `;` in list values
- Remove duplicate list options while preserving the first occurrence order

## Warning-only rules
- Inconsistent label casing
- Empty `Example enrichment`
- Very long option lists
