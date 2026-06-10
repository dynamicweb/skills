#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path


SKILL_ROOT = Path(__file__).resolve().parents[1]
SKILLS_ROOT = Path(__file__).resolve().parents[2]
for candidate in (SKILL_ROOT, SKILLS_ROOT):
    candidate_str = str(candidate)
    if candidate_str not in sys.path:
        sys.path.insert(0, candidate_str)

from shared_pim_core import (
    assert_clean_text,
    assert_single_payload_structure,
    dedupe_list_options,
    normalize_machine_id,
    read_xlsx,
    write_utf8_json,
)


FIELD_TYPE_IDS = {
    "Tekst (255)": 1,
    "Lang tekst": 2,
    "Kommatal": 7,
    "List": 15,
}


def allow_changes_across_languages(attribute_type: str) -> bool:
    return attribute_type in {"Kommatal", "List"}


def split_listbox_options(value: str) -> list[str]:
    if not value or not value.strip():
        return []
    return [item.strip() for item in value.split(";") if item.strip()]


def build_field_payload(workbook: dict) -> dict:
    payload = {
        "Path": workbook["Path"],
        "GlobalFields": [],
        "CategoryFields": [],
    }

    for row in workbook["Sheets"]["ProductAttributes"]:
        field_type = row.get("Field Type", "")
        if not field_type.strip():
            continue

        label = row.get("Attribute name", "")
        assert_clean_text(label, "ProductAttributes.Attribute name")
        options, _ = dedupe_list_options(split_listbox_options(row.get("Listbox Options", "")))
        item = {
            "AttributeName": label,
            "MachineId": normalize_machine_id(label),
            "Scope": field_type,
            "AttributeType": row.get("Attribute Type", ""),
            "Maintained": row.get("Maintained", ""),
            "PIMGroups": row.get("PIM Groups", ""),
            "ListboxOptions": options,
        }

        if field_type == "GF":
            payload["GlobalFields"].append(item)
        elif field_type == "CF":
            payload["CategoryFields"].append(item)

    return payload


def build_outputs(workbook: dict, field_payload: dict, omit_group_ids: set[str], shop_name: str) -> dict[str, dict]:
    product_groups = [
        row for row in workbook["Sheets"]["ProductGroups"]
        if row.get("GroupId", "").strip() and row.get("GroupId", "").strip() not in omit_group_ids
    ]

    name_by_id: dict[str, str] = {}
    parent_by_id: dict[str, str] = {}
    children_by_parent: dict[str, list[str]] = defaultdict(list)
    for row in product_groups:
        group_id = row["GroupId"].strip()
        group_name = row.get("GroupName", "")
        parent_group_id = row.get("ParentGroupId", "").strip()
        assert_clean_text(group_name, "ProductGroups.GroupName")
        name_by_id[group_id] = group_name
        parent_by_id[group_id] = parent_group_id
        if parent_group_id:
            children_by_parent[parent_group_id].append(group_id)

    folders = []
    categories = []
    links = []
    category_name_by_group_id: dict[str, str] = {}
    for row in product_groups:
        group_id = row["GroupId"].strip()
        if parent_by_id.get(group_id):
            continue

        parent_name = row.get("GroupName", "")
        data_models = []
        for child_id in children_by_parent.get(group_id, []):
            child_name = name_by_id[child_id]
            category_name = f"{parent_name}|{child_name}"
            assert_clean_text(child_name, "ProductGroups child GroupName")
            assert_clean_text(category_name, "Generated category display name")
            data_models.append({"name": child_name})
            categories.append({"name": category_name})
            links.append({
                "categoryName": category_name,
                "dataModelName": child_name,
                "folder": parent_name,
            })
            category_name_by_group_id[child_id] = category_name

        folders.append({"name": parent_name, "dataModels": data_models})

    all_data_model_names = []
    rule_data_model_names: dict[str, list[str]] = defaultdict(list)
    for group_id, category_name in sorted(category_name_by_group_id.items(), key=lambda item: item[1].lower()):
        data_model_name = name_by_id[group_id]
        all_data_model_names.append(data_model_name)
        rule_data_model_names[category_name].append(data_model_name)

    completion_rules = [{
        "name": "Global Fields",
        "excludeVariants": False,
        "fieldSystemNames": [field["MachineId"] for field in field_payload["GlobalFields"]],
        "dataModelNames": all_data_model_names,
    }]
    for category_name in sorted(rule_data_model_names.keys(), key=lambda item: item.lower()):
        completion_rules.append({
            "name": category_name,
            "excludeVariants": False,
            "fieldSystemNames": [],
            "dataModelNames": rule_data_model_names[category_name],
        })

    category_fields = []
    for field in field_payload["CategoryFields"]:
        field_name = field["AttributeName"]
        assert_clean_text(field_name, "Category field label")
        targets = []
        for group_id in split_listbox_options(field.get("PIMGroups", "")):
            if group_id in omit_group_ids:
                continue
            targets.append({
                "categoryName": category_name_by_group_id[group_id],
                "completenessNames": [category_name_by_group_id[group_id]],
            })

        item = {
            "id": field["MachineId"],
            "label": field_name,
            "templateTag": field["MachineId"],
            "type": FIELD_TYPE_IDS[field["AttributeType"]],
            "allowChangesAcrossLanguages": allow_changes_across_languages(field["AttributeType"]),
            "allowChangesAcrossVariants": False,
            "fieldRequired": False,
            "categories": targets,
        }
        if field.get("Maintained") in {"ERP", "DW"}:
            item["description"] = field["Maintained"]
        if field["AttributeType"] == "List":
            item["options"] = field["ListboxOptions"]
            item["presentation"] = "MultiSelectList"
        category_fields.append(item)

    product_fields = []
    for field in field_payload["GlobalFields"]:
        field_name = field["AttributeName"]
        assert_clean_text(field_name, "Global field label")
        item = {
            "id": field["MachineId"],
            "label": field_name,
            "templateTag": field["MachineId"],
            "type": FIELD_TYPE_IDS[field["AttributeType"]],
            "allowChangesAcrossLanguages": allow_changes_across_languages(field["AttributeType"]),
            "allowChangesAcrossVariants": False,
            "fieldRequired": False,
            "completenessNames": ["Global Fields"],
        }
        if field.get("Maintained") in {"ERP", "DW"}:
            item["description"] = field["Maintained"]
        if field["AttributeType"] == "List":
            item["options"] = field["ListboxOptions"]
            item["presentation"] = "MultiSelectList"
        product_fields.append(item)

    structure_payload = {
        "structure": {
            "shop": {"name": shop_name},
            "folders": folders,
            "categories": categories,
            "dataModelCategoryLinks": links,
            "categoryFields": category_fields,
            "productFields": product_fields,
            "completionRules": completion_rules,
        }
    }

    assert_single_payload_structure(
        structure_payload["structure"],
        context="Workbook to PIM Setup create_data_model_structure payload",
    )

    return {
        "workbook.json": workbook,
        "field-payload.json": field_payload,
        "create_data_model_structure.json": structure_payload,
        "summary.json": {
            "shop_name": shop_name,
            "top_level_folders": len(folders),
            "second_level_data_models": sum(len(folder["dataModels"]) for folder in folders),
            "categories": len(categories),
            "category_fields": len(category_fields),
            "product_fields": len(product_fields),
            "completion_rules": len(completion_rules),
            "single_payload_includes_product_fields": bool(structure_payload["structure"].get("productFields")),
            "omitted_group_ids": sorted(omit_group_ids),
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--shop-name", required=True)
    parser.add_argument("--omit-group-id", action="append", default=[])
    args = parser.parse_args()

    workbook = read_xlsx(args.path, ["ProductGroups", "ProductAttributes"])
    field_payload = build_field_payload(workbook)
    outputs = build_outputs(workbook, field_payload, set(args.omit_group_id), args.shop_name)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    for filename, value in outputs.items():
        write_utf8_json(output_dir / filename, value)

    print(json.dumps(outputs["summary.json"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
