# Provisioning And Verification

## Sequencing
Preserve this order:

1. Create or update one DataModel hierarchy and categories from `ProductGroups`
2. Create or update GF fields
3. Create or update CF fields and attach them to categories from `PIM Groups`
4. Create or update list options
5. Create or update completion rules
6. Build optional workspace or enrichment structures only if explicitly supported

Do not create a second catalog-group hierarchy that duplicates the DataModel hierarchy for the same workbook rows.

## Single-payload rule
Assemble the whole workbook into one complete intended payload before the first write.

- The complete intended payload must include shop, DataModel hierarchy, GF fields, CF fields, list options, and completion rules.
- Do not execute fieldwise, entitywise, or other partial writes as the primary provisioning strategy.
- If one complete payload-driven run is not possible with the available API or tooling, fail the run before write and report the blocker.

## Preflight QA gate
Verify the fully assembled intended payload before the first write.

- Check that all relevant technical ids contain only `a-z`, `0-9`, and `_`.
- Fail before write if any relevant technical id violates that rule.
- Apply this gate to product field system names, product category field system names, product category ids when used inside technical paths, list option values, and category-field completion-rule tokens.
- Do not apply this gate to human-readable display names.

## CF attachment and stamp verification
Before CF writes:

- Resolve and lock `GroupId -> CategoryId` for all involved second-level DataModels.

Verification gate:

- Build the expected `{CategoryId, FieldId}` matrix for all CF mappings from Excel.
- Read actual category fields.
- Verify each expected pair exists physically as `ProductCategory|<CategoryId>|<FieldId>`.
- Do not treat a shared or reference anchor alone as sufficient.

Fallback behavior in the same run:

- Retry only the missing pairs with explicit per-category field upsert.
- If the platform requires category re-initialization, do a controlled re-init and retry only the missing pairs.
- If any expected pair is still missing, fail the run and emit a blocking error list.

## List option rules
- Build option keys from normalization and upsert by `(FieldId, OptionValueKey)` for both GF and CF list fields.
- Persist option `Name` exactly as in Excel for both GF and CF list fields.
- Persist option `Value` as the normalized machine key derived from the Excel label for both GF and CF list fields.
- Sort option rows deterministically before write.
- If labels are numeric-like, sort from lowest to highest using numeric comparison rather than lexical string comparison.
- If both single numeric values and numeric intervals are present:
  - sort single values first from lowest to highest
  - sort interval values after the single values by interval start, then interval end
- If labels are primarily text-based, sort alphabetically `A-Z` by display label.
- If labels contain units or symbols, preserve the display label exactly and use only the extracted numeric meaning for ordering.
- Persist list presentation as `MultiSelectList` for both GF and CF list fields.
- Treat GF `productFields` and CF `categoryFields` identically for list presentation.
- Never swap `Name` and `Value`.
- For CF, upsert options once per unique field, not once per group mapping.
- Read back every persisted GF and CF list field after write and compare each `(Name, Value)` pair to the intended workbook mapping.
- Read back every persisted GF and CF list field after write and compare the persisted option order to the intended sorted order whenever the backend exposes option ordering.
- Read back every persisted GF and CF list field after write and compare the persisted list presentation to `MultiSelectList`.
- Verify exactly one row per `(FieldId, OptionValueKey)` after write.
- Treat any swapped `(Name, Value)` pair as a blocking error.
- Treat any persisted option-order mismatch as a blocking error unless the intended payload was correct and the mismatch is classified as probable `MCP/API/backend` behavior.
- Treat any persisted list presentation other than `MultiSelectList` as a blocking mismatch.
- Do not report success for list fields until the read-back verification passes or the user explicitly approves the mismatch in the current chat.

## Completion-rule rules
- Create one global rule for GF fields.
- Create category-specific rules for CF fields.
- Name the GF rule exactly `Global Fields`.
- Name each CF rule exactly as `<ParentGroupName>|<ChildGroupName>`, for example `Tennis|Tennis Racket`.
- Resolve the solution default eCommerce language id before any completion-rule assignment write.
- Use the locked `GroupId -> CategoryId` mapping from CF processing.
- Serialize CF rule fields as `ProductCategory|<CategoryId>|<AttributeSystemName>`.
- Use `CategoryId`, not `GroupId`, in CF completion-rule paths.
- Apply completion rules only on second-level groups or DataModels.
- When DataModels are the provisioned hierarchy, assign completion rules to the DataModel ids directly.
- Persist rule assignments to target second-level groups or DataModels through `GroupCompletionRules`.
- Persist the default language id into `GroupCompletionLanguageIds` on every target second-level group or DataModel that receives completion rules.
- Ensure the GF completion-rule id exists on all second-level groups or DataModels.
- Ensure category-specific completion rules exist only on relevant second-level groups or DataModels.
- Do not assign completion rules to first-level parent groups.
- Default `ExcludeVariants` to `false` unless the workbook or user explicitly requires otherwise.

## Idempotency
- Reruns must not duplicate entities.
- Upsert by stable id or system name.
- Add missing options only; never remove existing options.
- Update existing completion rules instead of appending duplicates.

## Intended-vs-persisted comparison
Build an explicit intended payload for every skill-critical artifact before write. After write, read back persisted values and compare them.

Always compare:

- Group display names
- Second-level DataModel names
- Category display names
- Category-specific completion-rule names
- `GroupCompletionLanguageIds`
- Option `Name` against the raw Excel label
- Option `Value` against the normalized machine key
- GF and CF descriptions
- Completion-rule field paths
- `GroupCompletionRules` assignments
- Data models tree shape, including absence of duplicated parallel nodes for the same workbook hierarchy

If the intended payload follows the skill but persisted data differs, classify it as probable `MCP/API/backend` behavior and do not report success for that artifact.

## Cleanup mode
Provide an optional scoped cleanup or reset mode for development and testing.

- Only affect entities created by this automation.
- Tag entities when creating them.
- Never run broad destructive cleanup by default.

## Logging and response format
Emit a structured run report with:

- Created and updated counts per entity type
- Validation summary with `auto_fixed`, `needs_input`, and `total_issues`
- Skill-compliance read-back summary with `intended`, `persisted`, and `mismatches`
- Post-run integrity checks for CF links, list options, naming, completion-rule coverage, and `GroupId -> CategoryId` mapping
- `missing_cf_pairs`
- `fallback_attempted`
- `fallback_retried_pairs_count`
- `fallback_success_pairs_count`
- `completion_rule_assignment_coverage`
- `mcp_suspected_issues` when relevant

Assistant response sections must be:

1. Validation report
2. Findings and assumptions
3. Proposed operation plan or payload
4. Approval checkpoint
5. Execution result
6. Post-run verification summary
7. CF stamp verification result
8. Skill-vs-persisted diff summary
