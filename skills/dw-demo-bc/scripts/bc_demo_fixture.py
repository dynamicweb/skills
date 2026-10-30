#!/usr/bin/env python3
"""WRITES: Owned local mock fixture with --apply only; requires Python 3.12+.

Owner: references/staged-sync.md. Parameters: --out (owned directory), --phase
baseline|changed|reset, --apply (write), --dry-run (explicit default).
Baseline and reset have identical business data; company-qualified keys survive
the changed phase. No ERP/Commerce/network operations. Not a BC API response.
Example: python scripts/bc_demo_fixture.py --out ./integration/mock --phase baseline --apply
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

OWNER = {"schema": 1, "owner": "dw-demo-bc"}
COMPANIES = ("00000000-0000-0000-0000-000000000011", "00000000-0000-0000-0000-000000000012")


def fixture(phase: str) -> dict:
    if phase not in {"baseline", "changed", "reset"}:
        raise ValueError("phase must be baseline, changed or reset")
    changed = phase == "changed"
    data: dict = {"schema": 1, "mode": "mock", "contract": "normalised rehearsal data, not a BC response",
                  "companies": [], "products": [], "customers": [], "shipTo": [], "prices": [],
                  "inventory": [], "bundles": [], "orders": [], "invoices": [], "creditContractExamples": []}
    for index, company in enumerate(COMPANIES):
        key = f"C{index + 1}"
        data["companies"].append({"id": company, "code": key, "currency": "EUR"})
        for number in ("ITEM100", "ITEM200"):
            data["products"].append({"companyId": company, "number": number, "uom": "PCS", "variant": "", "externalKey": f"{key}:{number}"})
        data["customers"].append({"companyId": company, "number": "CUST100", "group": "LAB", "externalKey": f"{key}:CUST100"})
        data["shipTo"].append({"companyId": company, "customer": "CUST100", "code": "PLANT1", "location": "MAIN", "owner": "BC"})
        for tier, amount in (("base", 12000), ("group", 11000), ("customer", 10000)):
            if changed and index == 0 and tier == "group":
                amount = 10500
            data["prices"].append({"companyId": company, "item": "ITEM100", "tier": tier, "amountMinor": amount,
                                   "currency": "EUR", "uom": "PCS", "minimumQuantity": 1, "owner": "BC"})
        data["inventory"].append({"companyId": company, "item": "ITEM100", "location": "MAIN", "uom": "PCS",
                                  "available": 7 if changed and index == 0 else 10})
        data["creditContractExamples"].append({"companyId": company, "customer": "CUST100", "state": "proposed",
                                               "note": "Requires an ERP-owned admission decision; not implemented by this mock."})
    data["bundles"].append({"number": "MARKETINGKIT", "owner": "Commerce", "amountMinor": 9000,
                            "components": [{"item": "ITEM100", "quantity": 1, "amountMinor": 4000},
                                           {"item": "ITEM200", "quantity": 1, "amountMinor": 5000}]})
    data["orders"].append({"companyId": COMPANIES[0], "sourceOrder": "MOCKORDER1", "erpOrder": "MOCKBC1",
                           "status": "partial shipment", "bundle": "MARKETINGKIT", "amountMinor": 9000,
                           "lines": [{"item": "ITEM100", "quantity": 1, "amountMinor": 4000},
                                     {"item": "ITEM200", "quantity": 1, "amountMinor": 5000}]})
    data["invoices"].append({"companyId": COMPANIES[0], "number": "MOCKINV1", "erpOrder": "MOCKBC1",
                             "sourceOrder": "MOCKORDER1", "amountMinor": 9000, "document": "mock only"})
    return data


def write_fixture(directory: Path, payload: str) -> None:
    """Write only our two named files; refuse an unrelated non-empty directory."""
    directory = directory.resolve()
    marker = directory / ".bc-demo-fixture.json"
    target = directory / "mock.json"
    if marker.is_symlink() or target.is_symlink():
        raise ValueError("fixture files must not be symbolic links")
    if directory.exists():
        if not directory.is_dir():
            raise ValueError("--out must name a directory")
        if marker.is_file():
            if json.loads(marker.read_text(encoding="utf-8")) != OWNER:
                raise ValueError("fixture ownership marker does not match dw-demo-bc")
        elif any(directory.iterdir()):
            raise ValueError("--out is not empty and has no dw-demo-bc ownership marker")
    directory.mkdir(parents=True, exist_ok=True)
    if not marker.exists():
        marker.write_text(json.dumps(OWNER) + "\n", encoding="utf-8")
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n", dir=directory, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(payload)
        os.replace(temporary, target)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--phase", choices=("baseline", "changed", "reset"), required=True)
    switches = parser.add_mutually_exclusive_group()
    switches.add_argument("--apply", action="store_true")
    switches.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    payload = json.dumps(fixture(args.phase), indent=2, sort_keys=True) + "\n"
    try:
        if args.apply:
            write_fixture(args.out, payload)
    except (OSError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    digest = hashlib.sha256(payload.encode("utf-8")).hexdigest()
    print(f"{'WROTE' if args.apply else 'DRY RUN'}: {args.out / 'mock.json'} phase={args.phase} mode=mock sha256={digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
