---
name: dynamicweb-pim-analysis-from-attribute-excel
description: Validates standardized Dynamicweb PIM attribute/group Excel data by finding concrete ProductGroups/ProductAttributes issues, applying only approved deterministic auto-fixes, and creating `*_FIXED.xlsx`, `Validation_Overview.csv`, and `Validation_Overview.xlsx`. Use when a user uploads or references a standardized `PIMConfiguration_*.xlsx` workbook and wants data validation before implementation; do not use this skill for implementation approval, shop naming, import-language confirmation, or repeated setup questions.
---

# Analysis - PIM Setup from Attribute Excel V2

## Objective
Validate standardized PIM Excel files that follow the expected ProductGroups and ProductAttributes layout.

- Treat the workbook as the single source of truth for analysis.
- Do not provision Dynamicweb entities from this skill.
- Do not run an implementation approval flow.
- Do not ask setup questions that belong in the implementation skill.
- Report concrete validation issues and allowed auto-fixes; do not list everything that is fine.
- Apply the Golden Standard v3 validation rules exactly.
- Auto-fix only the explicitly allowed cleanup cases.
- Produce both a fixed workbook and a structured issue overview.

## Shareability and prerequisites
Keep this skill portable and repository-safe.

- Use only bundled scripts and relative skill paths when referring to local resources.
- Assume the user may run this skill on Windows, macOS, Linux, or a hosted Codex environment.
- Python script dependencies for the bundled validator live in [`requirements.txt`](requirements.txt).
- Prefer the workbook explicitly provided by the user. If the environment exposes uploaded files in a standard upload directory, search there first; otherwise search the current workspace.
- Do not rely on machine-specific absolute paths, user-profile folders, or unpublished internal services.
- If the required workbook schema differs from this skill's contract, stop and explain the mismatch rather than guessing.

## First step on every run
Re-read this `SKILL.md` from disk at the start of every run.

- Treat the on-disk skill files as the only source of truth.
- Do not rely on memory, prior chat context, or earlier summaries.

## Input contract
Accept one workbook as input.

- Preferred filename pattern: `PIMConfiguration_*.xlsx`
- If the workbook was uploaded in a chat/file-upload environment, look in the environment's standard upload directory first.
- If not found there, look in the current workspace for the same filename pattern.
- If multiple matching files exist, use the first deterministic match after lexical sorting.
- If no matching workbook exists, stop and state that the required workbook was not found.

Read only these sheets:

- `ProductGroups`
- `ProductAttributes`

Ignore all other sheets without asking.

## Required columns
`ProductGroups` must contain:

- `GroupName`
- `GroupId`
- `ParentGroupId`

`ProductAttributes` must contain:

- `Attribute name`
- `Field Type`
- `Example enrichment`
- `Attribute Type`
- `Listbox Options`
- `Maintained`
- `PIM Groups`
- `Front-end filter`

## Execution workflow
Follow this order:

1. Locate the workbook.
2. Read `ProductGroups` and `ProductAttributes`.
3. Normalize text values with Unicode NFKC trimming rules.
4. Apply the Golden Standard v3 validation and auto-fix logic.
5. Write the fixed workbook and overview files beside the source workbook.
6. Report counts for auto-fixed items, needs-attention items, total issues, and output files.
7. Keep the response issue-focused; do not repeat valid rows, valid columns, or implementation decisions.

Use the bundled validator script when deterministic execution is helpful:
- [scripts/validate_golden_standard_v3.py](scripts/validate_golden_standard_v3.py)
- The validator accepts an explicit workbook path with `--path` and optional discovery hints with `--workspace` and `--upload-dir`.

## Mandatory validation rules
Apply these rules exactly.

### General normalization
- Normalize text using Unicode `NFKC`.
- Treat empty strings, whitespace-only strings, `None`, and `NaN` as blank.
- Normalize `GroupId` and `ParentGroupId` to strings and strip a trailing `.0`.
- Use case-insensitive existence checks for `GroupId` references.

### ProductGroups rules
- Capitalize the first letter of `GroupName` when the first character is lowercase. Record as an auto-fix and mark the overview row as `Ok`.
- If `GroupId` exists but `GroupName` is blank, record it as a needs-attention issue and mark the overview row as `Poor`.
- `GroupId` is mandatory. Blank `GroupId` is a needs-attention issue and must mark the overview row as `Poor`.
- `GroupId` must be ID-friendly: only `[A-Za-z0-9_-]`, and must not contain `--` or `__`.
- `ParentGroupId` must reference an existing `GroupId`.
- Duplicate `GroupId` values are invalid when compared case-insensitively.

### ProductAttributes rules
- Capitalize the first letter of `Attribute name` when the first character is lowercase. Record as an auto-fix and mark the overview row as `Ok`.
- If `Attribute name` is blank while other enrichment cells in the row contain values, record it as a needs-attention issue and mark the overview row as `Poor`.
- `Field Type` must be `GF`, `CF`, or blank.
- `Attribute Type` must be one of `List`, `Kommatal`, `Tekst (255)`, or `Lang tekst`.
- `Attribute Type` cannot be blank when `Attribute name` exists.
- If `Attribute Type = List`, `Listbox Options` must be filled.
- If `Attribute Type != List`, `Listbox Options` must be empty.
- Flag likely misplaced commas inside semicolon-separated `Listbox Options`, but do not auto-fix them.
- `Maintained` must be `DW`, `ERP`, or `Other` and cannot be blank.
- Normalize `PIM Groups` by converting commas to semicolons, trimming, deduplicating case-insensitively, and preserving order. Record as an auto-fix and mark the overview row as `Ok` when changed.
- Every `PIM Group` must exist in `ProductGroups[GroupId]`.
- `PIM Groups` must be empty when `Field Type = GF`.
- `PIM Groups` cannot be blank when `Field Type = CF`.
- `Front-end filter`, when filled, must be `Yes` or `No`.

## Auto-fix policy
Only auto-fix:

- First-letter capitalization for `GroupName`
- First-letter capitalization for `Attribute name`
- `PIM Groups` normalization:
  - commas to semicolons
  - trim whitespace
  - remove duplicates while preserving first occurrence order

Do not auto-fix any other issue.

## Output contract
Write these files beside the source workbook:

- `<OriginalName>_FIXED.xlsx`
- `Validation_Overview.csv`
- `Validation_Overview.xlsx`

The overview must cover every analyzed group/attribute row, even when no issue was found.

Use this exact column order:

- `Status`
- `sheet`
- `column`
- `row`
- `count`
- `issue`
- `example of issue`
- `proposed solution`
- `value before fix`
- `value after fix`

Status rules:

- Use only `Done`, `Ok`, or `Poor`.
- `Done` = the row/attribute/group setup and enrichment look satisfactory.
- `Ok` = usable but not perfect; there are smaller potential adjustments or input for possible solutions.
- `Poor` = there are clear data issues that should be described with a proposed solution.
- When `Status = Done`, populate only `Status`, `sheet`, and `column`. Leave every other field blank.
- When `Status != Done`, populate the relevant issue-enrichment fields: `row`, `count`, `issue`, `example of issue`, `proposed solution`, `value before fix`, and `value after fix`.

If no issues are found, still create the overview and mark each analyzed group/attribute row as `Done`.

## Question policy
Do not ask questions about:

- Extra sheets
- `Translations`
- Whether to clean valid data beyond the allowed auto-fixes
- Whether to auto-correct possible misplaced commas in listbox options
- Shop name, import language, write approval, field-type approval, completion rules, or other implementation setup choices

Only stop and ask the user if the required workbook is missing or unreadable.

## Response format
Respond in this order:

1. Workbook used
2. Validation summary
3. Auto-fixed items
4. Needs-attention items
5. Output files created

When summarizing validation results, align the wording with the overview status model:

- `Done`
- `Ok`
- `Poor`

Do not include an implementation approval checkpoint or a list of questions before write.
