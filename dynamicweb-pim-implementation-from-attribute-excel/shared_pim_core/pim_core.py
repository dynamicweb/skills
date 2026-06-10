from __future__ import annotations

import json
import re
import unicodedata
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path


NS = {
    "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "pkgrel": "http://schemas.openxmlformats.org/package/2006/relationships",
}

TRANSLITERATIONS = {
    "Ã¦": "ae",
    "Ã†": "ae",
    "Ã¸": "oe",
    "Ã˜": "oe",
    "Ã¥": "aa",
    "Ã…": "aa",
    "Ã¤": "ae",
    "Ã„": "ae",
    "Ã¶": "oe",
    "Ã–": "oe",
    "Ã¼": "ue",
    "Ãœ": "ue",
    "ÃŸ": "ss",
    "áºž": "ss",
}

MOJIBAKE_MARKERS = (
    "\ufffd",
    "Ãƒ",
    "Ã‚",
    "Ã¢",
)


def assert_clean_text(value: str, context: str) -> None:
    for marker in MOJIBAKE_MARKERS:
        if marker in value:
            raise ValueError(f"Detected broken text in {context}: {value!r}")


def normalize_machine_id(value: str) -> str:
    assert_clean_text(value, "NormalizeMachineId input")
    text = value.strip().lower()
    for source, target in TRANSLITERATIONS.items():
        text = text.replace(source, target)
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = re.sub(r"[^a-z0-9_]", "_", text)
    text = re.sub(r"_+", "_", text)[:255]
    if not text.strip():
        raise ValueError(f"NormalizeMachineId produced an empty value for {value!r}")
    return text


def split_excel_list_options(value: str, delimiter: str = ";") -> list[str]:
    if not value or not value.strip():
        return []
    return [item.strip() for item in value.split(delimiter) if item.strip()]


def _numeric_sort_key(label: str):
    normalized = label.strip().lower()
    if not re.match(r"^[<>]?\s*\d", normalized):
        return None
    matches = list(re.finditer(r"\d+(?:[.,]\d+)?", normalized))
    if not matches:
        return None

    first = float(matches[0].group(0).replace(",", "."))
    second = float(matches[1].group(0).replace(",", ".")) if len(matches) > 1 else 0.0
    between = normalized[matches[0].end():matches[1].start()] if len(matches) > 1 else ""

    if len(matches) == 1:
        return (0, first, 0.0, normalized)

    if re.search(r"[-â€“â€”]", between):
        return (1, first, second, normalized)

    if "x" in between:
        return (2, first, second, normalized)

    return (3, first, second, normalized)


def sort_option_labels(labels: list[str]) -> list[str]:
    cleaned = [label for label in labels if label and label.strip()]
    if not cleaned:
        return []

    numeric_keys = [_numeric_sort_key(label) for label in cleaned]
    if any(key is not None for key in numeric_keys):
        sortable = []
        fallback = []
        for label, key in zip(cleaned, numeric_keys):
            if key is None:
                fallback.append(label)
            else:
                sortable.append((key, label))
        ordered_numeric = [label for _, label in sorted(sortable, key=lambda item: item[0])]
        ordered_text = sorted(fallback, key=lambda label: label.lower())
        return ordered_numeric + ordered_text

    return sorted(cleaned, key=lambda label: label.lower())


def dedupe_list_options(labels: list[str]) -> tuple[list[dict[str, str]], list[str]]:
    options: list[dict[str, str]] = []
    dropped: list[str] = []
    seen: set[str] = set()

    for label in sort_option_labels(labels):
        assert_clean_text(label, "list option label")
        machine_value = normalize_machine_id(label)
        if machine_value in seen:
            dropped.append(label)
            continue
        seen.add(machine_value)
        options.append({"name": label, "value": machine_value})

    return options, dropped


def write_utf8_json(path: str | Path, value) -> None:
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def assert_single_payload_structure(structure: dict, *, context: str) -> None:
    if not isinstance(structure, dict):
        raise ValueError(f"{context}: expected a structure object")

    required_keys = (
        "shop",
        "folders",
        "categories",
        "dataModelCategoryLinks",
        "productFields",
        "categoryFields",
        "completionRules",
    )
    missing = [key for key in required_keys if key not in structure]
    if missing:
        raise ValueError(f"{context}: single-payload invariant violated, missing keys: {', '.join(missing)}")

    product_fields = structure.get("productFields")
    if product_fields is None or not isinstance(product_fields, list):
        raise ValueError(f"{context}: single-payload invariant violated, productFields must be a list")

    category_fields = structure.get("categoryFields")
    if category_fields is None or not isinstance(category_fields, list):
        raise ValueError(f"{context}: single-payload invariant violated, categoryFields must be a list")

    completion_rules = structure.get("completionRules")
    if completion_rules is None or not isinstance(completion_rules, list):
        raise ValueError(f"{context}: single-payload invariant violated, completionRules must be a list")


def _col_to_index(ref: str) -> int:
    letters = re.sub(r"\d", "", ref)
    value = 0
    for ch in letters:
        value = value * 26 + (ord(ch.upper()) - ord("A") + 1)
    return value


def _read_shared_strings(zf: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
    return ["".join(node.itertext()) for node in root.findall("main:si", NS)]


def _read_workbook(zf: zipfile.ZipFile) -> list[tuple[str, str]]:
    workbook = ET.fromstring(zf.read("xl/workbook.xml"))
    rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    rel_map = {rel.attrib["Id"]: rel.attrib["Target"] for rel in rels.findall("pkgrel:Relationship", NS)}
    sheets: list[tuple[str, str]] = []
    for sheet in workbook.findall("main:sheets/main:sheet", NS):
        rel_id = sheet.attrib["{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"]
        target = rel_map[rel_id].replace("\\", "/").lstrip("/")
        sheets.append((sheet.attrib["name"], target if target.startswith("xl/") else f"xl/{target}"))
    return sheets


def _cell_value(cell, shared_strings: list[str]) -> str:
    cell_type = cell.attrib.get("t", "")
    value = cell.find("main:v", NS)
    if cell_type == "s" and value is not None and value.text is not None:
        idx = int(value.text)
        return shared_strings[idx] if idx < len(shared_strings) else ""
    if cell_type == "inlineStr":
        is_node = cell.find("main:is", NS)
        return "".join(is_node.itertext()) if is_node is not None else ""
    return value.text if value is not None and value.text is not None else ""


def _read_sheet(zf: zipfile.ZipFile, path: str, shared_strings: list[str]) -> list[dict[str, str]]:
    root = ET.fromstring(zf.read(path))
    raw_rows: list[dict[int, str]] = []
    for row in root.findall("main:sheetData/main:row", NS):
        cells: dict[int, str] = {}
        for cell in row.findall("main:c", NS):
            ref = cell.attrib.get("r", "")
            if ref:
                cells[_col_to_index(ref)] = _cell_value(cell, shared_strings)
        raw_rows.append(cells)

    if not raw_rows:
        return []

    max_col = max((max(row.keys()) for row in raw_rows if row), default=0)
    headers = [str(raw_rows[0].get(idx, "")).strip() for idx in range(1, max_col + 1)]

    rows: list[dict[str, str]] = []
    for row_index, raw in enumerate(raw_rows[1:], start=2):
        item: dict[str, str] = {"RowNumber": row_index}
        for col_index, header in enumerate(headers, start=1):
            if not header:
                continue
            item[header] = str(raw.get(col_index, "")).strip()
        rows.append(item)
    return rows


def read_xlsx(path: str | Path, sheet_names: list[str] | None = None) -> dict:
    target = Path(path)
    with zipfile.ZipFile(target) as zf:
        shared_strings = _read_shared_strings(zf)
        sheets = _read_workbook(zf)
        if sheet_names is None:
            wanted = {name for name, _ in sheets}
        else:
            wanted = set(sheet_names)

        output = {"Path": str(target.resolve()), "Sheets": {}}
        sheet_map = {name: sheet_path for name, sheet_path in sheets}
        for sheet_name in wanted:
            if sheet_name not in sheet_map:
                raise ValueError(f"Sheet not found: {sheet_name}")
            output["Sheets"][sheet_name] = _read_sheet(zf, sheet_map[sheet_name], shared_strings)
        return output
