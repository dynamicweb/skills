#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path


SKILL_ROOT = Path(__file__).resolve().parents[1]
SKILLS_ROOT = Path(__file__).resolve().parents[2]
for candidate in (SKILL_ROOT, SKILLS_ROOT):
    candidate_str = str(candidate)
    if candidate_str not in sys.path:
        sys.path.insert(0, candidate_str)

from shared_pim_core import dedupe_list_options, normalize_machine_id, read_xlsx


def load_config(server_name: str, config_path: Path) -> tuple[str, list[str]]:
    if not config_path.exists():
        raise FileNotFoundError(
            f"MCP config file not found: {config_path}. Provide --endpoint and any needed --header values, "
            "or point --config-path to a valid Codex config."
        )
    config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    server = config["mcp_servers"][server_name]
    headers = [f"{key}: {value}" for key, value in server.get("http_headers", {}).items()]
    return server["url"], headers


def resolve_endpoint_and_headers(args: argparse.Namespace) -> tuple[str, list[str]]:
    explicit_headers = list(args.header)
    if args.endpoint:
        return args.endpoint, explicit_headers

    env_endpoint = os.environ.get("DW_MCP_ENDPOINT") or os.environ.get("MCP_ENDPOINT")
    if env_endpoint:
        env_headers = []
        for env_name in ("DW_MCP_HEADERS", "MCP_HEADERS"):
            raw = os.environ.get(env_name)
            if raw:
                env_headers.extend([item.strip() for item in raw.splitlines() if item.strip()])
        return env_endpoint, env_headers + explicit_headers

    endpoint, config_headers = load_config(args.server_name, Path(args.config_path).resolve())
    return endpoint, config_headers + explicit_headers


def parse_helper_payload(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    result = data.get("result")
    if not isinstance(result, dict):
        return result

    structured = result.get("structuredContent")
    if isinstance(structured, dict) and "result" in structured:
        return structured["result"]

    content = result.get("content")
    if isinstance(content, list):
        text_parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text" and item.get("text"):
                text_parts.append(str(item["text"]))
        if len(text_parts) == 1:
            text = text_parts[0]
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                return text
        if text_parts:
            return text_parts

    return result


def run_mcp_call(
    *,
    helper_path: Path,
    endpoint: str,
    headers: list[str],
    tool_name: str,
    arguments_file: Path,
    output_file: Path,
    timeout: int,
    progress: bool = False,
    log_file: Path | None = None,
    allow_failure: bool = False,
) -> tuple[int, object]:
    cmd = [
        sys.executable,
        str(helper_path),
        "--endpoint",
        endpoint,
        "--tool-name",
        tool_name,
        "--arguments-file",
        str(arguments_file),
        "--output-file",
        str(output_file),
        "--skip-initialize",
        "--timeout",
        str(timeout),
    ]
    for header in headers:
        cmd.extend(["--header", header])
    if progress:
        cmd.append("--progress")
    if log_file is not None:
        cmd.extend(["--log-file", str(log_file)])

    completed = subprocess.run(cmd, check=False)
    payload = parse_helper_payload(output_file)
    if completed.returncode != 0 and not allow_failure:
        raise RuntimeError(f"{tool_name} failed with exit code {completed.returncode}")
    return completed.returncode, payload


def export_payload_files(
    *,
    exporter_path: Path,
    workbook_path: Path,
    output_dir: Path,
    shop_name: str,
    omit_group_ids: list[str],
) -> dict:
    cmd = [
        sys.executable,
        str(exporter_path),
        "--path",
        str(workbook_path),
        "--output-dir",
        str(output_dir),
        "--shop-name",
        shop_name,
    ]
    for group_id in omit_group_ids:
        cmd.extend(["--omit-group-id", group_id])
    subprocess.run(cmd, check=True)
    return json.loads((output_dir / "summary.json").read_text(encoding="utf-8"))


def build_expected_rule_names(workbook: dict, omit_group_ids: set[str]) -> set[str]:
    product_groups = [
        row for row in workbook["Sheets"]["ProductGroups"]
        if row.get("GroupId", "").strip() and row.get("GroupId", "").strip() not in omit_group_ids
    ]
    name_by_id = {row["GroupId"].strip(): row.get("GroupName", "").strip() for row in product_groups}
    parent_by_id = {row["GroupId"].strip(): row.get("ParentGroupId", "").strip() for row in product_groups}

    expected = {"Global Fields"}
    for group_id, parent_id in parent_by_id.items():
        if not parent_id:
            continue
        expected.add(f"{name_by_id[parent_id]}|{name_by_id[group_id]}")
    return expected


def shop_completeness_score(shop: dict) -> tuple[int, int]:
    folders = shop.get("dataModels", [])
    data_model_count = sum(len(folder.get("dataModels", [])) for folder in folders)
    return data_model_count, len(folders)


def select_shop(shops: list[dict], shop_name: str) -> dict | None:
    candidates = [item for item in shops if item.get("name") == shop_name]
    if not candidates:
        return None
    # Duplicate names can exist after interrupted create attempts. Prefer the
    # richest tree so follow-up assignment targets the provisioned structure.
    return max(candidates, key=shop_completeness_score)


def normalize_category_id_part(value: str) -> str:
    text = re.sub(r"[^A-Za-z0-9_]", "_", value.strip())
    text = re.sub(r"_+", "_", text).strip("_")
    if not text:
        raise ValueError(f"Could not derive a category id part from {value!r}")
    return text


def derived_category_id(parent_name: str, child_name: str) -> str:
    return f"{normalize_category_id_part(parent_name)}{normalize_category_id_part(child_name)}"


def build_category_id_lookup(shop: dict) -> dict[tuple[str, str], str]:
    lookup = {}
    for folder in shop.get("dataModels", []):
        for data_model in folder.get("dataModels", []):
            key = (folder["name"], data_model["name"])
            lookup[key] = data_model.get("categoryId") or derived_category_id(*key)
    return lookup


def resolve_category_id(
    category_by_folder_child: dict[tuple[str, str], str],
    parent_name: str,
    child_name: str,
) -> str:
    # get_shops can return a compact tree without child data models. The persisted
    # category fields still use Dynamicweb's deterministic category id convention.
    return category_by_folder_child.get((parent_name, child_name)) or derived_category_id(parent_name, child_name)


def build_expected_cf_pairs(workbook: dict, omit_group_ids: set[str], shop: dict) -> set[tuple[str, str]]:
    product_groups = [
        row for row in workbook["Sheets"]["ProductGroups"]
        if row.get("GroupId", "").strip() and row.get("GroupId", "").strip() not in omit_group_ids
    ]
    name_by_id = {row["GroupId"].strip(): row.get("GroupName", "").strip() for row in product_groups}
    parent_by_id = {row["GroupId"].strip(): row.get("ParentGroupId", "").strip() for row in product_groups}

    category_by_folder_child = build_category_id_lookup(shop)

    expected_pairs: set[tuple[str, str]] = set()
    for row in workbook["Sheets"]["ProductAttributes"]:
        if row.get("Field Type", "").strip() != "CF":
            continue
        field_id = normalize_machine_id(row["Attribute name"])
        group_ids = [
            group_id.strip()
            for group_id in row.get("PIM Groups", "").split(";")
            if group_id.strip() and group_id.strip() not in omit_group_ids
        ]
        for group_id in group_ids:
            parent_name = name_by_id[parent_by_id[group_id]]
            child_name = name_by_id[group_id]
            category_id = resolve_category_id(category_by_folder_child, parent_name, child_name)
            expected_pairs.add((category_id, field_id))
    return expected_pairs


def build_expected_cf_option_map(workbook: dict, omit_group_ids: set[str], shop: dict) -> dict[tuple[str, str], list[tuple[str, str]]]:
    product_groups = [
        row for row in workbook["Sheets"]["ProductGroups"]
        if row.get("GroupId", "").strip() and row.get("GroupId", "").strip() not in omit_group_ids
    ]
    name_by_id = {row["GroupId"].strip(): row.get("GroupName", "").strip() for row in product_groups}
    parent_by_id = {row["GroupId"].strip(): row.get("ParentGroupId", "").strip() for row in product_groups}

    category_by_folder_child = build_category_id_lookup(shop)

    option_map: dict[tuple[str, str], list[tuple[str, str]]] = {}
    for row in workbook["Sheets"]["ProductAttributes"]:
        if row.get("Field Type", "").strip() != "CF":
            continue
        labels = [item.strip() for item in row.get("Listbox Options", "").split(";") if item.strip()]
        options, _ = dedupe_list_options(labels)
        if not options:
            continue
        field_id = normalize_machine_id(row["Attribute name"])
        group_ids = [
            group_id.strip()
            for group_id in row.get("PIM Groups", "").split(";")
            if group_id.strip() and group_id.strip() not in omit_group_ids
        ]
        for group_id in group_ids:
            parent_name = name_by_id[parent_by_id[group_id]]
            child_name = name_by_id[group_id]
            category_id = resolve_category_id(category_by_folder_child, parent_name, child_name)
            option_map[(category_id, field_id)] = [(option["name"], option["value"]) for option in options]
    return option_map


def build_assignment_requests(shop: dict, rules: list[dict]) -> dict:
    rule_id_by_name = {rule["name"]: rule["id"] for rule in rules}
    global_rule_id = rule_id_by_name["Global Fields"]
    requests = []
    for folder in shop["dataModels"]:
        folder_name = folder["name"]
        for data_model in folder.get("dataModels", []):
            rule_name = f"{folder_name}|{data_model['name']}"
            requests.append(
                {
                    "groupId": data_model["id"],
                    "languageIds": ["ENU"],
                    "ruleIds": [global_rule_id, rule_id_by_name[rule_name]],
                }
            )
    return {"requests": requests}


def verify_state(
    *,
    workbook: dict,
    omit_group_ids: set[str],
    summary: dict,
    shops: list[dict],
    rules: list[dict],
    category_fields: list[dict],
    standard_fields: list[dict],
    shop_name: str,
) -> dict:
    shop = select_shop(shops, shop_name)
    expected_rule_names = build_expected_rule_names(workbook, omit_group_ids)

    verification = {
        "shop_found": shop is not None,
        "shop_id": shop.get("id") if shop else None,
        "matching_shops": sum(1 for item in shops if item.get("name") == shop_name),
        "folders_expected": summary["top_level_folders"],
        "folders_actual": 0,
        "data_models_expected": summary["second_level_data_models"],
        "data_models_actual": 0,
        "gf_expected": summary["product_fields"],
        "gf_missing": [],
        "rules_expected": len(expected_rule_names),
        "rules_missing": [],
        "expected_cf_pairs": 0,
        "actual_cf_pairs": 0,
        "missing_cf_pairs": [],
        "cf_option_mismatches": [],
        "cf_option_verification_supported": True,
        "cf_option_verification_note": None,
        "shop_tree_complete": False,
        "shop_tree_note": None,
        "is_complete": False,
    }
    if not shop:
        return verification

    verification["folders_actual"] = len(shop["dataModels"])
    verification["data_models_actual"] = sum(len(folder.get("dataModels", [])) for folder in shop["dataModels"])
    verification["shop_tree_complete"] = (
        verification["folders_actual"] == verification["folders_expected"]
        and verification["data_models_actual"] == verification["data_models_expected"]
    )
    if not verification["shop_tree_complete"]:
        verification["shop_tree_note"] = (
            "get_shops returned a compact or partial tree; persisted fields and completion rules are used "
            "as the authoritative completeness checks."
        )

    expected_gf = [
        normalize_machine_id(row["Attribute name"])
        for row in workbook["Sheets"]["ProductAttributes"]
        if row.get("Field Type", "").strip() == "GF"
    ]
    standard_field_ids = {field["systemName"] for field in standard_fields}
    verification["gf_missing"] = sorted(field_id for field_id in expected_gf if field_id not in standard_field_ids)

    rule_names = {rule["name"] for rule in rules}
    verification["rules_missing"] = sorted(expected_rule_names - rule_names)

    expected_cf_pairs = build_expected_cf_pairs(workbook, omit_group_ids, shop)
    verification["expected_cf_pairs"] = len(expected_cf_pairs)
    actual_cf_pairs = {
        (field["categoryId"], field["systemName"].split("|")[-1])
        for field in category_fields
    }
    verification["actual_cf_pairs"] = len(actual_cf_pairs)
    verification["missing_cf_pairs"] = sorted(expected_cf_pairs - actual_cf_pairs)

    expected_cf_option_map = build_expected_cf_option_map(workbook, omit_group_ids, shop)
    actual_cf_option_map = {}
    actual_option_field_count = 0
    for field in category_fields:
        options = field.get("options") or []
        if options:
            actual_option_field_count += 1
            key = (field["categoryId"], field["systemName"].split("|")[-1])
            actual_cf_option_map[key] = [(item["label"], item["value"]) for item in options]

    mismatches = []
    if expected_cf_option_map and actual_option_field_count == 0:
        verification["cf_option_verification_supported"] = False
        verification["cf_option_verification_note"] = (
            "get_product_category_fields did not return list options, so option values were not used as an "
            "automatic completeness gate. The create payload still includes the workbook list options."
        )
    else:
        for key, expected in expected_cf_option_map.items():
            if actual_cf_option_map.get(key) != expected:
                mismatches.append(
                    {
                        "categoryId": key[0],
                        "fieldId": key[1],
                        "expected": expected,
                        "actual": actual_cf_option_map.get(key),
                    }
                )
    verification["cf_option_mismatches"] = mismatches

    verification["is_complete"] = all(
        [
            verification["shop_found"],
            not verification["gf_missing"],
            not verification["rules_missing"],
            not verification["missing_cf_pairs"],
            not verification["cf_option_mismatches"],
        ]
    )
    return verification


def main() -> None:
    parser = argparse.ArgumentParser(description="Provision a PIM workbook with resumable create/assign flow.")
    parser.add_argument("--path", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--shop-name", required=True)
    parser.add_argument("--server-name", default="jfa")
    parser.add_argument("--config-path", default=str(Path.home() / ".codex" / "config.toml"))
    parser.add_argument("--endpoint", help="Explicit MCP endpoint URL. Overrides config discovery.")
    parser.add_argument(
        "--header",
        action="append",
        default=[],
        help="Optional HTTP header in 'Name: Value' format. Can be provided multiple times.",
    )
    parser.add_argument("--omit-group-id", action="append", default=[])
    parser.add_argument("--create-timeout", type=int, default=240)
    parser.add_argument("--read-timeout", type=int, default=120)
    parser.add_argument(
        "--allow-duplicate-shop-create",
        action="store_true",
        help=(
            "Allow create_data_model_structure even when a shop with the requested name already exists. "
            "Use only when intentionally creating a parallel shop, because some MCP implementations create a "
            "duplicate instead of updating the existing shop."
        ),
    )
    parser.add_argument(
        "--allow-multiple-matching-shops",
        action="store_true",
        help=(
            "Allow the run to continue when more than one existing shop has the requested name. "
            "By default this is blocked to avoid writing into an ambiguous duplicate-shop state."
        ),
    )
    args = parser.parse_args()

    workbook_path = Path(args.path).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    omit_group_ids = set(args.omit_group_id)

    exporter_path = Path(__file__).with_name("export_payload_files.py")
    helper_path = Path(__file__).with_name("mcp_call.py")
    endpoint, headers = resolve_endpoint_and_headers(args)

    summary = export_payload_files(
        exporter_path=exporter_path,
        workbook_path=workbook_path,
        output_dir=output_dir,
        shop_name=args.shop_name,
        omit_group_ids=list(omit_group_ids),
    )
    workbook = read_xlsx(workbook_path, ["ProductGroups", "ProductAttributes"])

    empty_args_path = output_dir / "empty_args.json"
    empty_args_path.write_text("{}\n", encoding="utf-8")

    def fetch_state() -> tuple[list[dict], list[dict], list[dict], list[dict]]:
        _, shops = run_mcp_call(
            helper_path=helper_path,
            endpoint=endpoint,
            headers=headers,
            tool_name="get_shops",
            arguments_file=empty_args_path,
            output_file=output_dir / "get_shops_live.json",
            timeout=args.read_timeout,
        )
        _, rules = run_mcp_call(
            helper_path=helper_path,
            endpoint=endpoint,
            headers=headers,
            tool_name="get_completion_rules",
            arguments_file=empty_args_path,
            output_file=output_dir / "get_completion_rules_live.json",
            timeout=args.read_timeout,
        )
        _, category_fields = run_mcp_call(
            helper_path=helper_path,
            endpoint=endpoint,
            headers=headers,
            tool_name="get_product_category_fields",
            arguments_file=empty_args_path,
            output_file=output_dir / "get_product_category_fields_live.json",
            timeout=args.read_timeout,
        )
        _, standard_fields = run_mcp_call(
            helper_path=helper_path,
            endpoint=endpoint,
            headers=headers,
            tool_name="get_standard_fields",
            arguments_file=empty_args_path,
            output_file=output_dir / "get_standard_fields_live.json",
            timeout=args.read_timeout,
        )
        return shops, rules, category_fields, standard_fields

    shops, rules, category_fields, standard_fields = fetch_state()
    verification = verify_state(
        workbook=workbook,
        omit_group_ids=omit_group_ids,
        summary=summary,
        shops=shops,
        rules=rules,
        category_fields=category_fields,
        standard_fields=standard_fields,
        shop_name=args.shop_name,
    )

    if verification["matching_shops"] > 1 and not args.allow_multiple_matching_shops:
        (output_dir / "verification_duplicate_shops_blocked.json").write_text(
            json.dumps(verification, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        raise RuntimeError(
            f"Multiple shops named {args.shop_name!r} already exist on the target solution. "
            "Stop and clean up the duplicate shops before provisioning, or rerun with "
            "--allow-multiple-matching-shops only if the ambiguity is intentional."
        )

    if not verification["is_complete"]:
        if verification["shop_found"] and not args.allow_duplicate_shop_create:
            (output_dir / "verification_pre_create_blocked.json").write_text(
                json.dumps(verification, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            raise RuntimeError(
                f"Shop {args.shop_name!r} already exists but is not complete. "
                "create_data_model_structure may create a duplicate shop instead of updating the existing one. "
                "Review verification_pre_create_blocked.json and rerun with --allow-duplicate-shop-create only "
                "if a parallel shop is intentional."
            )
        create_output = output_dir / "create_data_model_structure_result.json"
        create_code, _ = run_mcp_call(
            helper_path=helper_path,
            endpoint=endpoint,
            headers=headers,
            tool_name="create_data_model_structure",
            arguments_file=output_dir / "create_data_model_structure.json",
            output_file=create_output,
            timeout=args.create_timeout,
            progress=True,
            log_file=output_dir / "create_data_model_structure_run.log",
            allow_failure=True,
        )

        shops, rules, category_fields, standard_fields = fetch_state()
        verification = verify_state(
            workbook=workbook,
            omit_group_ids=omit_group_ids,
            summary=summary,
            shops=shops,
            rules=rules,
            category_fields=category_fields,
            standard_fields=standard_fields,
            shop_name=args.shop_name,
        )
        if create_code != 0 and not verification["is_complete"]:
            raise RuntimeError(
                "create_data_model_structure returned an error and the persisted state is still incomplete."
            )

    shop = select_shop(shops, args.shop_name)
    if shop is None:
        raise RuntimeError(f"Could not find shop {args.shop_name!r} after provisioning.")
    assign_payload = build_assignment_requests(shop, rules)
    assign_path = output_dir / "assign_completion_rules_to_groups.json"
    assign_path.write_text(json.dumps(assign_payload, ensure_ascii=False, indent=2), encoding="utf-8")

    _, assign_result = run_mcp_call(
        helper_path=helper_path,
        endpoint=endpoint,
        headers=headers,
        tool_name="assign_completion_rules_to_groups",
        arguments_file=assign_path,
        output_file=output_dir / "assign_completion_rules_to_groups_result.json",
        timeout=args.create_timeout,
    )

    shops, rules, category_fields, standard_fields = fetch_state()
    verification = verify_state(
        workbook=workbook,
        omit_group_ids=omit_group_ids,
        summary=summary,
        shops=shops,
        rules=rules,
        category_fields=category_fields,
        standard_fields=standard_fields,
        shop_name=args.shop_name,
    )
    verification["assignment_result"] = assign_result
    (output_dir / "verification_summary.json").write_text(
        json.dumps(verification, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps(verification, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
