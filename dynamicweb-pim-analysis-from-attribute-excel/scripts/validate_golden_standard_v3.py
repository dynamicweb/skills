from __future__ import annotations

import argparse
import os
import re
import unicodedata
from pathlib import Path

import pandas as pd


PRODUCT_GROUP_COLUMNS = [
    "GroupName",
    "GroupId",
    "ParentGroupId",
]

PRODUCT_ATTRIBUTE_COLUMNS = [
    "Attribute name",
    "Field Type",
    "Example enrichment",
    "Attribute Type",
    "Listbox Options",
    "Maintained",
    "PIM Groups",
    "Front-end filter",
]

OVERVIEW_COLUMNS = [
    "Status",
    "sheet",
    "column",
    "row",
    "count",
    "issue",
    "example of issue",
    "proposed solution",
    "value before fix",
    "value after fix",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate standardized PIM configuration workbooks.")
    parser.add_argument("--path", help="Explicit path to the workbook to validate.")
    parser.add_argument("--workspace", default=".", help="Workspace directory used when auto-discovering the workbook.")
    parser.add_argument(
        "--upload-dir",
        action="append",
        default=[],
        help="Optional upload directory to search before the workspace. Can be provided multiple times.",
    )
    return parser.parse_args()


def discover_workbook(explicit_path: str | None, workspace: str, upload_dirs: list[str]) -> Path:
    if explicit_path:
        candidate = Path(explicit_path).expanduser().resolve()
        if not candidate.exists():
            raise FileNotFoundError(f"Workbook not found: {candidate}")
        return candidate

    search_roots: list[Path] = []
    for raw in upload_dirs:
        if raw:
            search_roots.append(Path(raw).expanduser())

    for env_name in ("CODEX_UPLOAD_DIR", "UPLOAD_DIR"):
        env_value = os.environ.get(env_name)
        if env_value:
            search_roots.append(Path(env_value).expanduser())

    search_roots.extend(
        [
            Path("/mnt/data"),
            Path(workspace).expanduser(),
            Path.cwd(),
        ]
    )

    matches: list[Path] = []
    seen: set[str] = set()
    for root in search_roots:
        try:
            resolved_root = root.resolve()
        except OSError:
            continue
        if not resolved_root.exists() or not resolved_root.is_dir():
            continue
        for match in sorted(resolved_root.glob("PIMConfiguration_*.xlsx")):
            resolved_match = match.resolve()
            key = str(resolved_match).lower()
            if key not in seen:
                seen.add(key)
                matches.append(resolved_match)

    if not matches:
        raise FileNotFoundError("No Excel file found with naming pattern 'PIMConfiguration_*.xlsx'")
    return matches[0]


def excel_row(idx: int) -> int:
    return idx + 2


def is_blank(value) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return unicodedata.normalize("NFKC", value).strip() == ""
    try:
        if pd.isna(value):
            return True
    except Exception:
        pass
    return False


def to_str_or_empty(value) -> str:
    if is_blank(value):
        return ""
    return unicodedata.normalize("NFKC", str(value)).strip()


def normalize_id(value) -> str:
    result = to_str_or_empty(value)
    if result.endswith(".0"):
        result = result[:-2]
    return result


def is_id_friendly(value: str) -> bool:
    if is_blank(value):
        return False
    cleaned = to_str_or_empty(value)
    if "--" in cleaned or "__" in cleaned:
        return False
    return re.fullmatch(r"[A-Za-z0-9_-]+", cleaned) is not None


def first_cap(value: str) -> str:
    if is_blank(value):
        return value
    cleaned = to_str_or_empty(value)
    return cleaned[0].upper() + cleaned[1:] if cleaned else cleaned


def split_semicolon_list(value: str) -> list[str]:
    cleaned = to_str_or_empty(value).replace(",", ";")
    parts = [part.strip() for part in cleaned.split(";")]
    result: list[str] = []
    seen: set[str] = set()
    for part in parts:
        if not part:
            continue
        key = part.casefold()
        if key in seen:
            continue
        seen.add(key)
        result.append(part)
    return result


def listbox_has_misplaced_comma(value: str) -> bool:
    cleaned = to_str_or_empty(value)
    if not cleaned or ";" not in cleaned:
        return False

    options = [option.strip() for option in cleaned.split(";") if option.strip()]
    for option in options:
        if "," not in option:
            continue
        if re.search(r"\d\s*,\s*\d", option):
            continue
        parts = [part.strip() for part in option.split(",") if part.strip()]
        if len(parts) >= 2:
            score = 0
            for part in parts[:10]:
                if len(part) <= 40 and re.search(r"[A-Za-z0-9]", part):
                    score += 1
            if score >= 2:
                return True
    return False


def ensure_required_columns(frame: pd.DataFrame, required_columns: list[str], sheet_name: str) -> None:
    missing = [column for column in required_columns if column not in frame.columns]
    if missing:
        raise ValueError(f"{sheet_name} is missing required columns: {', '.join(missing)}")


def normalize_frame(frame: pd.DataFrame) -> pd.DataFrame:
    normalize_value = lambda value: to_str_or_empty(value) if isinstance(value, str) or not is_blank(value) else value
    if hasattr(frame, "map"):
        return frame.map(normalize_value)
    return frame.applymap(normalize_value)


def make_issue(
    *,
    status: str,
    sheet: str,
    column: str,
    row: int,
    issue: str,
    proposed_solution: str,
    example: str = "",
    before: str = "",
    after: str = "",
) -> dict[str, object]:
    return {
        "Status": status,
        "sheet": sheet,
        "column": column,
        "row": row,
        "count": 1,
        "issue": issue,
        "example of issue": example,
        "proposed solution": proposed_solution,
        "value before fix": before,
        "value after fix": after,
    }


def make_done_row(sheet: str, column: str) -> dict[str, object]:
    return {
        "Status": "Done",
        "sheet": sheet,
        "column": column,
        "row": "",
        "count": "",
        "issue": "",
        "example of issue": "",
        "proposed solution": "",
        "value before fix": "",
        "value after fix": "",
    }


def add_issue(
    issues: list[dict[str, object]],
    row_issue_map: dict[tuple[str, int], list[dict[str, object]]],
    fixed_count: list[int],
    needs_attention_count: list[int],
    issue: dict[str, object],
) -> None:
    issues.append(issue)
    row_key = (str(issue["sheet"]), int(issue["row"]))
    row_issue_map.setdefault(row_key, []).append(issue)
    if issue["Status"] == "Ok":
        fixed_count[0] += 1
    elif issue["Status"] == "Poor":
        needs_attention_count[0] += 1


def summarize_row_issues(row_issues: list[dict[str, object]]) -> dict[str, object]:
    if not row_issues:
        raise ValueError("Cannot summarize an empty issue list")
    status = "Poor" if any(issue["Status"] == "Poor" for issue in row_issues) else "Ok"
    first = row_issues[0]
    last_after = ""
    for issue in row_issues:
        if issue["value after fix"]:
            last_after = str(issue["value after fix"])
    return {
        "Status": status,
        "sheet": first["sheet"],
        "column": ", ".join(dict.fromkeys(str(issue["column"]) for issue in row_issues)),
        "row": first["row"],
        "count": len(row_issues),
        "issue": " | ".join(str(issue["issue"]) for issue in row_issues),
        "example of issue": " | ".join(str(issue["example of issue"]) for issue in row_issues if issue["example of issue"]),
        "proposed solution": " | ".join(
            str(issue["proposed solution"]) for issue in row_issues if issue["proposed solution"]
        ),
        "value before fix": " | ".join(str(issue["value before fix"]) for issue in row_issues if issue["value before fix"]),
        "value after fix": last_after,
    }


def validate_workbook(workbook_path: Path) -> tuple[pd.DataFrame, pd.DataFrame, list[dict[str, object]], int, int]:
    xls = pd.ExcelFile(workbook_path)
    product_groups = pd.read_excel(xls, sheet_name="ProductGroups")
    product_attributes = pd.read_excel(xls, sheet_name="ProductAttributes")

    ensure_required_columns(product_groups, PRODUCT_GROUP_COLUMNS, "ProductGroups")
    ensure_required_columns(product_attributes, PRODUCT_ATTRIBUTE_COLUMNS, "ProductAttributes")

    product_groups = normalize_frame(product_groups)
    product_attributes = normalize_frame(product_attributes)

    product_groups["GroupId"] = product_groups["GroupId"].apply(normalize_id)
    product_groups["ParentGroupId"] = product_groups["ParentGroupId"].apply(normalize_id)

    issues: list[dict[str, object]] = []
    row_issue_map: dict[tuple[str, int], list[dict[str, object]]] = {}
    fixed_count = [0]
    needs_attention_count = [0]

    gid_norms = product_groups["GroupId"].apply(normalize_id)
    gid_ci_set = set(gid_norms.str.lower().tolist())

    for idx, row in product_groups.iterrows():
        group_name = row.get("GroupName")
        group_id = normalize_id(row.get("GroupId"))
        parent_group_id = normalize_id(row.get("ParentGroupId"))
        row_number = excel_row(idx)
        group_name_str = to_str_or_empty(group_name)

        if not is_blank(group_name) and group_name_str and group_name_str[0].islower():
            fixed_value = first_cap(group_name_str)
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Ok",
                    sheet="ProductGroups",
                    column="GroupName",
                    row=row_number,
                    issue="First letter must be capitalized.",
                    proposed_solution="Use capitalized GroupName. The workbook can be saved with the corrected value.",
                    example=group_name_str,
                    before=group_name_str,
                    after=fixed_value,
                ),
            )
            product_groups.at[idx, "GroupName"] = fixed_value

        if not is_blank(group_id) and is_blank(group_name):
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductGroups",
                    column="GroupName",
                    row=row_number,
                    issue="GroupName must be filled when GroupId exists.",
                    proposed_solution="Fill in GroupName for this group row.",
                    example=group_id,
                ),
            )

        if is_blank(group_id):
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductGroups",
                    column="GroupId",
                    row=row_number,
                    issue="GroupId is mandatory.",
                    proposed_solution="Provide a unique ID-friendly GroupId using letters, numbers, underscores, or hyphens.",
                ),
            )
        elif not is_id_friendly(group_id):
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductGroups",
                    column="GroupId",
                    row=row_number,
                    issue="GroupId must be ID-friendly.",
                    proposed_solution="Use only letters, numbers, underscores, or hyphens, and avoid repeated separators.",
                    example=group_id,
                ),
            )

        if not is_blank(parent_group_id) and parent_group_id.lower() not in gid_ci_set:
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductGroups",
                    column="ParentGroupId",
                    row=row_number,
                    issue="ParentGroupId does not exist in ProductGroups[GroupId].",
                    proposed_solution="Change ParentGroupId so it references an existing GroupId.",
                    example=parent_group_id,
                ),
            )

    gid_lower = gid_norms.str.lower()
    duplicate_mask = gid_lower.duplicated(keep=False) & gid_lower.ne("")
    for idx, is_duplicate in duplicate_mask.items():
        if is_duplicate:
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductGroups",
                    column="GroupId",
                    row=excel_row(idx),
                    issue="Duplicate GroupId detected case-insensitively.",
                    proposed_solution="Make each GroupId unique across ProductGroups.",
                    example=to_str_or_empty(product_groups.at[idx, "GroupId"]),
                ),
            )

    valid_field_types = {"gf", "cf", ""}
    valid_attr_types = {"list", "kommatal", "tekst (255)", "lang tekst"}
    valid_maintained = {"dw", "erp", "other"}

    for idx, row in product_attributes.iterrows():
        name = row.get("Attribute name")
        field_type = to_str_or_empty(row.get("Field Type")).lower()
        attribute_type = to_str_or_empty(row.get("Attribute Type")).lower()
        listbox_options = row.get("Listbox Options")
        maintained = to_str_or_empty(row.get("Maintained")).lower()
        pim_groups = row.get("PIM Groups")
        front_end_filter = to_str_or_empty(row.get("Front-end filter")).lower()
        row_number = excel_row(idx)

        name_str = to_str_or_empty(name)
        pim_groups_str = to_str_or_empty(pim_groups)
        listbox_options_str = to_str_or_empty(listbox_options)

        if not is_blank(name_str) and name_str[0].islower():
            fixed_value = first_cap(name_str)
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Ok",
                    sheet="ProductAttributes",
                    column="Attribute name",
                    row=row_number,
                    issue="First letter must be capitalized.",
                    proposed_solution="Use a capitalized attribute label. The workbook can be saved with the corrected value.",
                    example=name_str,
                    before=name_str,
                    after=fixed_value,
                ),
            )
            product_attributes.at[idx, "Attribute name"] = fixed_value
            name_str = fixed_value

        other_values = [
            field_type,
            row.get("Example enrichment"),
            attribute_type,
            listbox_options,
            maintained,
            pim_groups,
            front_end_filter,
        ]
        if is_blank(name_str) and any(not is_blank(value) for value in other_values):
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="Attribute name",
                    row=row_number,
                    issue="Attribute name must be filled if the row contains enrichment data.",
                    proposed_solution="Provide an attribute label or remove the remaining row content.",
                ),
            )

        if field_type not in valid_field_types:
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="Field Type",
                    row=row_number,
                    issue="Field Type must be GF, CF, or blank.",
                    proposed_solution="Set Field Type to GF, CF, or leave it blank.",
                    example=to_str_or_empty(row.get("Field Type")),
                ),
            )

        if not is_blank(attribute_type) and attribute_type not in valid_attr_types:
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="Attribute Type",
                    row=row_number,
                    issue="Invalid or misspelled Attribute Type.",
                    proposed_solution="Use one of the supported values: List, Kommatal, Tekst (255), or Lang tekst.",
                    example=attribute_type,
                ),
            )

        if not is_blank(name_str) and is_blank(attribute_type):
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="Attribute Type",
                    row=row_number,
                    issue="Attribute Type cannot be blank when Attribute name exists.",
                    proposed_solution="Choose the correct Attribute Type for the attribute row.",
                ),
            )

        if not is_blank(attribute_type) and attribute_type == "list" and is_blank(listbox_options_str):
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="Listbox Options",
                    row=row_number,
                    issue="Attribute Type is List but Listbox Options is empty.",
                    proposed_solution="Provide one or more semicolon-separated list options.",
                ),
            )

        if not is_blank(attribute_type) and attribute_type != "list" and not is_blank(listbox_options_str):
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="Listbox Options",
                    row=row_number,
                    issue="Listbox Options must be empty when Attribute Type is not List.",
                    proposed_solution="Clear Listbox Options or change Attribute Type to List.",
                    example=listbox_options_str,
                ),
            )

        if not is_blank(listbox_options_str) and attribute_type == "list" and listbox_has_misplaced_comma(listbox_options_str):
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="Listbox Options",
                    row=row_number,
                    issue="Possible misplaced comma inside semicolon-separated Listbox Options.",
                    proposed_solution="Review the option separators manually and keep option groups semicolon-separated.",
                    example=listbox_options_str,
                ),
            )

        if is_blank(maintained) or maintained not in valid_maintained:
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="Maintained",
                    row=row_number,
                    issue="Maintained must be DW, ERP, or Other.",
                    proposed_solution="Set Maintained to DW, ERP, or Other.",
                    example=maintained,
                ),
            )

        if not is_blank(pim_groups_str):
            normalized_groups = split_semicolon_list(pim_groups_str)
            normalized_value = ";".join(normalized_groups)
            if normalized_value != pim_groups_str:
                add_issue(
                    issues,
                    row_issue_map,
                    fixed_count,
                    needs_attention_count,
                    make_issue(
                        status="Ok",
                        sheet="ProductAttributes",
                        column="PIM Groups",
                        row=row_number,
                        issue="PIM Groups normalized for separators, trimming, and duplicate removal.",
                        proposed_solution="Keep semicolon-separated PIM Groups with trimmed unique values.",
                        example=pim_groups_str,
                        before=pim_groups_str,
                        after=normalized_value,
                    ),
                )
                product_attributes.at[idx, "PIM Groups"] = normalized_value
                pim_groups_str = normalized_value

            for group_value in normalized_groups:
                if group_value.lower() not in gid_ci_set:
                    add_issue(
                        issues,
                        row_issue_map,
                        fixed_count,
                        needs_attention_count,
                        make_issue(
                            status="Poor",
                            sheet="ProductAttributes",
                            column="PIM Groups",
                            row=row_number,
                            issue=f"PIM Group '{group_value}' does not exist in ProductGroups[GroupId].",
                            proposed_solution="Replace the unknown PIM Group value with an existing GroupId.",
                            example=group_value,
                        ),
                    )

        if field_type == "gf" and not is_blank(pim_groups_str):
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="PIM Groups",
                    row=row_number,
                    issue="PIM Groups must be empty when Field Type is GF.",
                    proposed_solution="Clear PIM Groups for global fields.",
                    example=pim_groups_str,
                ),
            )

        if field_type == "cf" and is_blank(pim_groups_str):
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="PIM Groups",
                    row=row_number,
                    issue="PIM Groups cannot be blank when Field Type is CF.",
                    proposed_solution="Assign one or more ProductGroups GroupIds to the CF field.",
                ),
            )

        if not is_blank(front_end_filter) and front_end_filter not in {"yes", "no"}:
            add_issue(
                issues,
                row_issue_map,
                fixed_count,
                needs_attention_count,
                make_issue(
                    status="Poor",
                    sheet="ProductAttributes",
                    column="Front-end filter",
                    row=row_number,
                    issue="Front-end filter must be Yes or No when filled.",
                    proposed_solution="Set Front-end filter to Yes or No, or leave it blank.",
                    example=front_end_filter,
                ),
            )

    overview_rows: list[dict[str, object]] = []
    for idx in range(len(product_groups)):
        row_number = excel_row(idx)
        row_issues = row_issue_map.get(("ProductGroups", row_number), [])
        if row_issues:
            overview_rows.append(summarize_row_issues(row_issues))
        else:
            overview_rows.append(make_done_row("ProductGroups", "GroupName, GroupId, ParentGroupId"))

    for idx in range(len(product_attributes)):
        row_number = excel_row(idx)
        row_issues = row_issue_map.get(("ProductAttributes", row_number), [])
        if row_issues:
            overview_rows.append(summarize_row_issues(row_issues))
        else:
            overview_rows.append(make_done_row("ProductAttributes", "Attribute row"))

    overview = pd.DataFrame(overview_rows, columns=OVERVIEW_COLUMNS)
    return product_groups, product_attributes, overview.to_dict("records"), fixed_count[0], needs_attention_count[0]


def main() -> None:
    args = parse_args()
    workbook_path = discover_workbook(args.path, args.workspace, args.upload_dir)
    fixed_xlsx = workbook_path.parent / f"{workbook_path.stem}_FIXED.xlsx"
    overview_csv = workbook_path.parent / "Validation_Overview.csv"
    overview_xlsx = workbook_path.parent / "Validation_Overview.xlsx"

    print(f"Using Excel file: {workbook_path.name}")

    product_groups, product_attributes, overview_rows, fixed_count, needs_attention_count = validate_workbook(workbook_path)
    overview = pd.DataFrame(overview_rows, columns=OVERVIEW_COLUMNS)

    overview.to_csv(overview_csv, index=False)
    try:
        import xlsxwriter  # noqa: F401
        excel_engine = "xlsxwriter"
    except ModuleNotFoundError:
        excel_engine = "openpyxl"

    with pd.ExcelWriter(overview_xlsx, engine=excel_engine) as writer:
        overview.to_excel(writer, sheet_name="Validation Overview", index=False)
    with pd.ExcelWriter(fixed_xlsx, engine=excel_engine) as writer:
        product_groups.to_excel(writer, sheet_name="ProductGroups", index=False)
        product_attributes.to_excel(writer, sheet_name="ProductAttributes", index=False)

    total_issues = sum(1 for row in overview_rows if row["Status"] != "Done")
    done_count = sum(1 for row in overview_rows if row["Status"] == "Done")
    ok_count = sum(1 for row in overview_rows if row["Status"] == "Ok")
    poor_count = sum(1 for row in overview_rows if row["Status"] == "Poor")

    print("\nValidation summary")
    print(f"- Done: {done_count}")
    print(f"- Ok: {ok_count}")
    print(f"- Poor: {poor_count}")
    print(f"- Auto-fixed items: {fixed_count}")
    print(f"- Needs-attention items: {needs_attention_count}")
    print(f"- Total issues: {total_issues}")
    print("\nOutput files created")
    print(f"- {fixed_xlsx.name}")
    print(f"- {overview_csv.name}")
    print(f"- {overview_xlsx.name}")


if __name__ == "__main__":
    main()
