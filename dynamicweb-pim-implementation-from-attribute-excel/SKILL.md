---
name: dynamicweb-pim-implementation-from-attribute-excel
description: Builds a Dynamicweb PIM setup from a standardized attribute and group Excel file. Use when a configuration Excel file defines the groups, fields, options, and rules that should be created in the solution.
---

# Implementation - PIM Setup from Attribute Excel V2

## Objective
Implement Dynamicweb PIM automation in code with Excel as the single runtime input.

- Do not use SQL staging tables, views, or integration jobs as the execution method.
- Use SQL, XML, DOCX, and process material only as behavioral reference for the intended end state.
- Provision PIM configuration only unless the user explicitly asks for product import.
- Treat the initial workbook prompt as configuration-only by default and do not ask whether product import should happen.

## Shareability and prerequisites
Keep this skill portable and partner-safe when published in a repository.

- Use only bundled scripts, bundled references, and documented external tools.
- Use relative skill paths when referring to local resources.
- Do not assume a specific local username, workstation path, or operating system.
- Python script dependencies for bundled helpers live in [`requirements.txt`](requirements.txt).
- If duplicate same-name shops must be cleaned up, use the bundled helper [`scripts/cleanup_duplicate_shops.py`](scripts/cleanup_duplicate_shops.py) instead of ad hoc deletion steps.
- Treat this skill as reusable only when the runtime has access to:
  - the workbook input
  - the bundled scripts and references in this skill folder
  - the bundled local fallback package [`shared_pim_core/pim_core.py`](shared_pim_core/pim_core.py)
  - Dynamicweb APIs, repositories, or services that can read and write the required PIM entities
  - a reachable MCP or equivalent API endpoint for the target Dynamicweb environment
- If required Dynamicweb tools or API capabilities are unavailable, stop and report the missing prerequisite before any write.
- If helper tool names differ across environments, map them to the equivalent capability instead of assuming the exact internal tool name exists.
- If authentication, base URLs, or HTTP headers are required, require them through explicit runtime configuration rather than hardcoding environment secrets into the skill.
- Accept endpoint and authentication details from explicit runtime configuration such as command arguments, environment variables, or the local Codex MCP setup.

## First step on every run
Re-read this `SKILL.md` from disk at the start of every implementation run.

- Treat the on-disk skill files as the only source of truth.
- Do not rely on memory, prior chat context, or earlier cached summaries.
- Use the versioned scripts in [`scripts/export-payload-files.ps1`](scripts/export-payload-files.ps1) and [`scripts/export_payload_files.py`](scripts/export_payload_files.py) for workbook parsing, normalization, and payload-file generation instead of ad hoc inline parsing.
- Shared normalization, list-option mapping, and UTF-8 guards live in [`shared_pim_core/pim_core.py`](shared_pim_core/pim_core.py) and must not be reimplemented ad hoc in prompts or temporary snippets.
- Do not implement transliteration with inline non-ASCII literals in temporary shell or Python snippets. Keep transliteration logic in versioned script files using stable codepoint-based definitions.
- Do not pipe workbook JSON through mixed-runtime stdout parsing when building implementation payloads. Generate UTF-8 payload files on disk with the versioned Python exporter and read those files directly.

## Input contract
Accept flexible workbook names such as:

- `PIM_Configuration_Automation_CustomerName.xlsx`
- `PIM_Configuration_CustomerName.xlsx`
- Any `.xlsx` where the last meaningful filename token identifies the project

Read only these sheets:

- `ProductGroups`
- `ProductAttributes`

Ignore all other sheets, including `Translations`, without asking.

For the exact workbook schema and filename parsing rules, read:
- [references/excel-contract-and-mapping.md](references/excel-contract-and-mapping.md)

## Supporting references
Read these source materials in this order when they are available in the task context:

1. Workbook input contract
2. `Step1_ExcelDataPreparationGuide_CustomerName.docx`, if the user or repository actually provides it
3. `PIMAutomationProcess_EN.docx`, if the user or repository actually provides it
4. `HowToImplement.docx`, if the user or repository actually provides it
5. SQL reference files
6. XML integration-job reference files
7. Optional customer-specific scope docs

Use them only to understand the intended result. Do not switch to SQL or XML execution.
If one or more optional supporting documents are absent, continue with the workbook, bundled references, and available Dynamicweb runtime capabilities.

## Execution workflow
Follow this order for design and provisioning runs:

1. Call `get_field_types`
2. Call `get_standard_fields`
3. Confirm or ask what the PIM shop should be called going forward if the user has not already named it explicitly
4. Validate workbook
5. Build one complete intended payload and operation plan for the entire workbook
6. Ask for explicit approval
7. Execute one approved run
8. Read back persisted state and compare it to the intended payload before reporting success

If the environment does not expose tools literally named `get_field_types` or `get_standard_fields`, use the equivalent documented capability that returns:

- supported Dynamicweb field types
- the standard field inventory already present in the target solution

## Mandatory implementation stance
- Build or update code in the Dynamicweb solution.
- Use Dynamicweb services, repositories, or APIs directly.
- Treat the intended PIM shop name as unique solution state.
- If no shop with the intended name exists, the run may create it.
- If exactly one shop with the intended name exists, treat that shop as the only valid update target.
- If more than one shop with the intended name exists, stop before any write and treat that as a cleanup blocker until the duplicates are removed or the user explicitly approves a parallel-shop scenario.
- Do not create a same-name duplicate shop as an implicit retry strategy.
- Derive a best-guess shop name from the last meaningful token in the workbook filename after removing separators `_`, `-`, and spaces and ignoring `pim`, `configuration`, and `automation`.
- If the user has not already provided a clear shop name, ask in the first assistant response what the PIM shop should be called going forward and include the derived best guess as the recommended proposal.
- If the intended shop name is explicitly confirmed by the user, use that name instead of the derived guess.
- Import Excel values exactly as provided unless a hard-fail rule blocks the run or the explicitly allowed workbook value cleanup below applies.
- Do not omit, skip, filter out, defer, or silently drop any workbook attribute, regardless of `Maintained`, enrichment ownership, or perceived suitability, unless the user has explicitly approved that omission in the current chat after you asked a concrete clarification question about the specific issue.
- Do not introduce fallback heuristics that are not defined in this skill.
- For this PIM flow, create one DataModel hierarchy only. Do not create a parallel catalog-group hierarchy that duplicates the same nodes.
- Do not call `save_groups` for the workbook hierarchy when the purpose is PIM/DataModels provisioning.
- Assign completion rules to the created DataModel ids directly.
- Always create completion rules from the workbook unless the user explicitly asks to omit them in the current chat.
- Build the entire workbook as one complete intended payload before the first write. The payload must include shop, DataModel hierarchy, GF fields, CF fields, list options, and completion rules.
- Do not execute field-by-field, entity-by-entity, or other partial-write strategies as the primary provisioning method.
- If the available Dynamicweb API or tooling cannot support one complete payload-driven run without breaking this skill's invariants, stop before the first write and report a blocker instead of degrading to partial writes.
- Treat list-option mapping as a strict invariant for both GF and CF list fields:
  - `Name = Excel label` exactly as entered in the workbook
  - `Value = NormalizeMachineId(ExcelLabel)`
  - Payloads that send `Name = normalized key` and `Value = Excel label` are invalid for this skill
  - If a tool example, legacy implementation, or prior run contradicts this mapping, do not follow it
  - Never swap, reinterpret, or auto-correct these directions without explicit user approval in the current chat

## Naming rules
Apply distinct naming rules for second-level DataModels versus category groups and completion rules.

- First-level parent display name must be `ProductGroups.GroupName` exactly.
- Second-level DataModel display name must be the child `ProductGroups.GroupName` exactly.
- Category group display name for a second-level item must be `<ParentGroupName>|<ChildGroupName>`.
- Completion rule display name for a second-level category-specific rule must be `<ParentGroupName>|<ChildGroupName>`.
- `Global Fields` remains the only allowed GF completion-rule name.
- Normalize only technical ids. Do not normalize or alter display names except for the required parent-child concatenation on category groups and category-specific completion rules.

Example for parent `Tennis` and child `Tennis Racket`:

- Group/DataModel name: `Tennis Racket`
- Category group name: `Tennis|Tennis Racket`
- Completion rule name: `Tennis|Tennis Racket`

Read the detailed mapping rules here:
- [references/excel-contract-and-mapping.md](references/excel-contract-and-mapping.md)

## Normalization and validation
Use one shared normalization function named `NormalizeMachineId` for all technical identifiers.

- Keep human-readable labels exactly as entered in Excel.
- Normalize only machine identifiers.
- Run a preflight QA gate on the fully assembled intended payload before the first write.
- Hard-fail the preflight QA gate if any expected technical id contains characters outside `a-z`, `0-9`, and `_`.
- Apply that QA gate to product field system names, product category field system names, product category ids when they participate in technical paths or system names, list option values, and category-field completion-rule tokens.
- Do not apply that QA gate to human-readable display names such as shop names, group names, DataModel names, or category display names.
- Hard-fail on invalid schema, invalid value domains, empty normalized ids, scope collisions, broken `GroupId -> CategoryId` mapping, missing CF physical stamps, incorrect completion-rule serialization, invalid technical ids, and any attempt to execute partial writes instead of the complete intended payload.
- Auto-fix only the explicitly allowed cleanup cases.

Read the exact normalization algorithm and validation matrix here:
- [references/normalization-and-validation.md](references/normalization-and-validation.md)

## Provisioning, verification, and idempotency
Preserve the provisioning sequencing:

1. Create or update one DataModel hierarchy from `ProductGroups`
2. Create or update GF fields
3. Create or update CF fields and attach them to categories
4. Create or update list options
5. Create or update completion rules
6. Perform optional workspace or enrichment structures only if explicitly supported

Additional requirements:

- Lock a deterministic `GroupId -> CategoryId` mapping before CF and completion-rule work.
- Resolve the solution default eCommerce language id before assigning completion rules to groups or DataModels.
- When assigning completion rules to groups or DataModels, always persist the solution default language id into `GroupCompletionLanguageIds`.
- Assemble the entire workbook into one complete intended payload before the first write.
- The complete intended payload must cover shop, DataModel hierarchy, GF fields, CF fields, list options, and completion rules.
- Do not execute fieldwise or other partial writes as the primary strategy.
- If one complete payload-driven run is not possible, fail the run before write and report the blocker.
- Verify every expected CF physical stamp as `ProductCategory|<CategoryId>|<FieldId>`.
- Verify every persisted GF and CF list field by reading it back and comparing each option pair against the intended workbook mapping.
- Treat any swapped list-option `Name` and `Value` pair as a blocking error, not a warning.
- Do not report success for a run until list-option mapping has been explicitly verified or the user has explicitly approved a known mismatch.
- Retry only missing CF pairs through the controlled fallback defined by this skill.
- Upsert by stable ids and avoid duplicate entities on reruns.
- Compare intended and persisted values for all skill-critical artifacts and classify mismatches as probable `MCP/API/backend` issues when the intended payload follows the skill.
- Treat duplicate top-level nodes in the Data models tree as a blocking error, not a warning.
- Treat multiple shops with the same intended PIM shop name as a blocking error, not a warning.

## Workbook value cleanup
- Trim leading and trailing whitespace from every workbook cell value before validation, payload assembly, and write.
- Trim leading and trailing whitespace from each split list-option token before creating list options.
- Normalize spaces around `;` in list values as part of the existing auto-fix behavior.
- Preserve meaningful internal whitespace inside labels and technical values, such as display names, attribute names, and option labels.
- Treat this trimming as implementation-safe cleanup, not as a user-facing value transformation that requires approval.

Read the exact sequencing, fallback, verification, and logging requirements here:
- [references/provisioning-and-verification.md](references/provisioning-and-verification.md)

## Question policy
Ask only about things that safely change the concrete provisioning result.

If the PIM shop name is not already explicit in the current chat, ask about it in the first assistant response before approval and before any write.

- Phrase it as a concrete naming decision for the PIM shop going forward.
- Include the best derived shop-name guess from the workbook filename as the recommended option.
- Treat the answer as provisioning-affecting because the shop name becomes persisted solution state.

If one or more existing shops already use the intended PIM shop name, do not silently create another same-name shop.

- If exactly one matching shop exists, tell the user the run will target that existing shop.
- If multiple matching shops exist, stop and ask for cleanup or an explicit parallel-shop decision before any write.

Do not ask about:

- Non-required sheets
- `Translations`
- `Front-end filter`
- Whether valid Excel data should be cleaned or reduced
- Whether completion rules should be handled differently
- Mandatory fields or field-required behavior
- Whether product import should happen on the initial prompt; assume configuration-only unless the user later explicitly requests product import
- Shop naming after the user has already explicitly confirmed it in the current chat

You must ask the user before proceeding if you identify any concrete implementation concern that would cause one or more workbook attributes to be omitted, skipped, transformed beyond the skill rules, or only partially provisioned.

- Name the exact affected attribute ids or labels.
- State why the issue is problematic.
- Ask for explicit approval before excluding or altering them.
- If approval is not granted, treat the situation as unresolved and do not report success.
- The same approval rule applies to any detected list-option mismatch, including swapped `Name` and `Value`.

Approval-question style:

- Keep pre-write responses short and concrete.
- Prefer one concise `Proposed operation plan` section plus one numbered `Approval checkpoints` section.
- Do not add a separate `Findings and assumptions` section unless it introduces new information that is not already obvious from the plan.
- Approval checkpoints must be numbered `1.`, `2.`, `3.` and each point must describe one concrete provisioning decision or blocker.
- Do not add an attribute-review table for this skill, because the workbook already defines attribute types directly.

## Extended field settings
Apply these field-setting rules to every workbook-driven run.

- Treat `Maintained` as the source for read-only behavior.
- If `Maintained` resolves to `ERP` or `Source ERP`, mark the field as read only.
- If `Maintained` resolves to `DW`, `Dynamicweb`, `Other`, or blank, do not infer read-only from `Maintained`.
- Apply language inheritance by field type:
  - `listbox` and `decimal` must inherit across languages
  - `editor` and `text255` must not inherit across languages
- If a field resolves to another supported type such as `longtext` or `date`, do not invent a new inheritance rule. Keep the baseline default unless the user explicitly overrides it.
- Keep `allowChangesAcrossVariants = false` unless the user explicitly overrides it.
- Treat these rules as part of the intended payload and verification target, not as optional heuristics.

## Safety defaults
Use these defaults unless the user explicitly overrides them:

- `allowChangesAcrossLanguages = false` as the baseline default before applying the field-type-specific inheritance rules above
- `allowChangesAcrossVariants = false`
- `fieldRequired = false`

## List presentation invariant
Treat listbox presentation as a hard invariant across both scopes.

- Every listbox field must request and persist `MultiSelectList`.
- This applies equally to:
  - GF listbox fields created as `productFields`
  - CF listbox fields created as `categoryFields`
- Do not rely on backend defaults for list presentation.
- Always set `presentation = MultiSelectList` explicitly for every intended listbox field in the write payload.
- Read back both GF and CF listbox fields after write and verify the persisted presentation value.
- If a GF or CF listbox field reads back as `RadioButtonList`, `DropDownList`, `CheckBoxList`, or any value other than `MultiSelectList`, treat that as a verification failure.
- If the intended payload explicitly requested `MultiSelectList` and the persisted value still differs, classify that artifact as probable `MCP/API/backend` behavior rather than a skill-compliance success.

## List option sorting invariant
Treat listbox option ordering as a hard invariant across both scopes.

- Sort every GF and CF listbox option set deterministically before write.
- If the option labels are numeric-like, sort from lowest to highest using numeric comparison rather than lexical string comparison.
- Example:
  - `1, 2, 3, ..., 10, 11, 12`
  - not `1, 10, 11, 12, 2`
- If the option labels contain both single numeric values and numeric intervals:
  - sort all single numeric values first from lowest to highest
  - then sort interval values from lowest to highest by interval start
- Examples:
  - `70, 80, 90` must persist in that order
  - `1, 2, 3, 10, 11, 12, 1-100, 200-300`
- Treat labels such as `70`, `80`, `90`, `1-100`, `10-20`, `2700`, `3000`, `4000`, `2700-6500`, and `80-130 lm/W` as candidates for numeric sorting when the ordering intent is measurable or ordinal.
- If the option labels are primarily text-based, sort alphabetically `A-Z` by the human-readable label.
- If labels contain units or symbols, preserve the original label exactly and use only the extracted numeric meaning for ordering.
- Do not preserve workbook encounter order unless the user explicitly asks for source-order persistence.
- Read back persisted GF and CF list fields after write and verify option order whenever the backend exposes ordering.
- If the intended payload sorted options correctly and the persisted order still differs, classify that artifact as probable `MCP/API/backend` behavior rather than a skill-compliance success.

## Deliverables
Produce:

- Import service, module, or class
- Reusable validation component
- Reusable mapping component
- Unit tests for validation and normalization
- Integration tests where feasible

## Assistant response format
Respond in this order:

1. Validation report
2. Shop-name checkpoint, when the PIM shop name is not already explicit, including the recommended best guess
3. Proposed operation plan or payload
4. Approval checkpoints
5. Execution result
6. Post-run verification summary
7. CF stamp verification result
8. Skill-vs-persisted diff summary, including an explicit `MCP/API/backend` note when relevant
