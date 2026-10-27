#!/usr/bin/env python3
"""READ-ONLY. Validate local BC acceptance evidence; requires Python 3.12+.

Owner: references/verification.md. No ERP calls or file writes. Rejects missing
coverage, mock/live confusion, stale reports, escaping or duplicate proof files.
Parameters: --spec, --evidence, --mode live|mock, --max-age-hours (default 24).
Example: python scripts/verify_bc_acceptance.py --spec spec.json --evidence run.json --mode live
Exit 0 means structural evidence checks passed; proof content still needs review.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import math
from pathlib import Path, PureWindowsPath
import sys
from uuid import UUID

SCENARIOS = frozenset({
    "authentication", "products", "customers", "ship_to", "tier_prices",
    "promotions", "inventory", "fulfilment", "bundles", "credit",
    "order_export", "status", "invoices", "replay", "isolation",
})


def nonempty_guid(value: object) -> str:
    if not isinstance(value, str):
        raise ValueError("GUID must be a string")
    guid = UUID(value)
    if not guid.int:
        raise ValueError("empty GUID is not a selected identity")
    return str(guid)


def validate(spec: dict, report: dict, proof_root: Path, mode: str,
             max_age_hours: float = 24, now: datetime | None = None) -> list[str]:
    """Return actionable failures. Reports and specs are untrusted local JSON."""
    errors: list[str] = []
    if not math.isfinite(max_age_hours) or max_age_hours <= 0:
        return ["max-age-hours must be finite and positive"]
    if mode not in {"mock", "live"}:
        return ["mode must be mock or live"]
    if not isinstance(spec, dict) or not isinstance(report, dict):
        return ["spec and evidence must be JSON objects"]
    if type(spec.get("schema")) is not int or spec["schema"] != 1:
        errors.append("spec schema must be integer 1")
    if type(report.get("schema")) is not int or report["schema"] != 1:
        errors.append("evidence schema must be integer 1")
    try:
        tenant = nonempty_guid(spec.get("tenantId"))
        if nonempty_guid(report.get("tenantId")) != tenant:
            errors.append("evidence tenant does not match spec")
    except (ValueError, AttributeError, TypeError):
        errors.append("spec and evidence need non-empty tenant GUIDs")
    environment = spec.get("environment")
    if not isinstance(environment, str) or not environment.strip():
        errors.append("spec needs an environment name")
    elif report.get("environment") != environment:
        errors.append("evidence environment does not match spec")
    if report.get("mode") != mode:
        errors.append(f"evidence mode must be {mode}; mock evidence cannot prove live integration")

    raw_companies = spec.get("companyIds")
    companies: set[str] = set()
    if not isinstance(raw_companies, list) or not raw_companies:
        errors.append("spec companyIds must be a non-empty list")
    else:
        try:
            companies = {nonempty_guid(value) for value in raw_companies}
            if len(companies) != len(raw_companies):
                errors.append("spec companyIds contains duplicate companies")
        except (ValueError, TypeError, AttributeError):
            errors.append("spec companyIds must contain non-empty GUIDs")

    required = spec.get("requiredScenarios")
    if not isinstance(required, list) or not required or any(not isinstance(x, str) for x in required):
        errors.append("spec requiredScenarios must be a non-empty string list")
        required = []
    elif len(required) != len(set(required)) or not set(required) <= SCENARIOS:
        errors.append("spec requiredScenarios contains duplicate or unknown scenario IDs")

    now = now or datetime.now(timezone.utc)
    try:
        measured = datetime.fromisoformat(report.get("measuredAt", "").replace("Z", "+00:00"))
        if measured.tzinfo is None or measured.utcoffset() != timedelta(0):
            errors.append("measuredAt must include a UTC timezone")
        elif measured > now + timedelta(minutes=5) or now - measured > timedelta(hours=max_age_hours):
            errors.append("evidence is stale or future-dated; collect a fresh run")
    except (ValueError, TypeError, AttributeError, OverflowError):
        errors.append("measuredAt must be an ISO UTC timestamp")

    results = report.get("results")
    if not isinstance(results, list):
        return errors + ["evidence results must be an array"]
    seen: set[tuple[str, str]] = set()
    root = proof_root.resolve()
    for index, result in enumerate(results):
        label = f"result {index}"
        if not isinstance(result, dict):
            errors.append(f"{label} must be an object")
            continue
        scenario = result.get("scenario")
        if not isinstance(scenario, str) or scenario not in SCENARIOS:
            errors.append(f"{label} has an unknown scenario")
            continue
        try:
            company = nonempty_guid(result.get("companyId"))
        except (ValueError, TypeError, AttributeError):
            errors.append(f"{label} needs a non-empty company GUID")
            continue
        label = f"{scenario}/{company}"
        key = (scenario, company)
        if company not in companies:
            errors.append(f"{label} is outside the spec company allowlist")
        if key in seen:
            errors.append(f"{label} has duplicate results")
        seen.add(key)
        if result.get("passed") is not True:
            errors.append(f"{label} did not pass (use a JSON boolean)")
        if result.get("mode", mode) != mode:
            errors.append(f"{label} has a conflicting evidence mode")
        if not isinstance(result.get("assertion"), str) or not result["assertion"].strip():
            errors.append(f"{label} needs a concrete assertion")
        proofs = result.get("proofs")
        if not isinstance(proofs, list) or len(proofs) < 2:
            errors.append(f"{label} needs at least two independent proof files")
            continue
        paths: set[Path] = set()
        hashes: set[str] = set()
        for value in proofs:
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{label} has an invalid proof path")
                continue
            relative = Path(value)
            if relative.is_absolute() or PureWindowsPath(value).drive:
                errors.append(f"{label} proof must be relative to the evidence directory")
                continue
            path = (root / relative).resolve()
            if not path.is_relative_to(root) or path == root:
                errors.append(f"{label} proof escapes the evidence directory")
                continue
            if not path.is_file() or path.stat().st_size == 0:
                errors.append(f"{label} proof is missing or empty: {value}")
                continue
            paths.add(path)
            with path.open("rb") as stream:
                hashes.add(hashlib.file_digest(stream, "sha256").hexdigest())
        if len(paths) < 2 or len(hashes) < 2:
            errors.append(f"{label} proofs must resolve to distinct files with different content")
    for scenario in required:
        for company in sorted(companies):
            if (scenario, company) not in seen:
                errors.append(f"missing {scenario}/{company}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--mode", choices=("live", "mock"), required=True)
    parser.add_argument("--max-age-hours", type=float, default=24)
    args = parser.parse_args()
    try:
        spec = json.loads(args.spec.read_text(encoding="utf-8"))
        report = json.loads(args.evidence.read_text(encoding="utf-8"))
        errors = validate(spec, report, args.evidence.parent, args.mode, args.max_age_hours)
    except (OSError, ValueError, TypeError, OverflowError) as error:
        print(f"FAIL: cannot validate evidence: {error}", file=sys.stderr)
        return 1
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"PASS: {len(report['results'])} {args.mode} results have complete structural evidence; review proof contents.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
