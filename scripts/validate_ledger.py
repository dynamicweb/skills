"""Read-only ledger validation, called by validate-skills.py. Uses PowerShell 7 Test-Json
for draft-7 schemas (also available in the repository CI), and stdlib for cross-file rules.
No target connection, generated files, or third-party Python dependencies.
"""
import json
import re
import subprocess
from pathlib import Path


EDIT_LAYOUT_ASPECTS = ("screen-type", "editors-resolve", "family-tabs", "tabs-per-family", "scannable", "names",
                       "catch-all", "unique-group-names", "division")


def layout_argument_faults(handler, arguments) -> list[str]:
    """The limits an edit-layout or field-placement rule needs are data on the binding, never code.
    The runner repeats these checks (Test-PimLayoutArguments) and also compiles the banned patterns."""
    args = arguments if isinstance(arguments, dict) else {}

    def positive(key):
        return isinstance(args.get(key), int) and not isinstance(args.get(key), bool) and args[key] > 0

    if handler == "pim-field-placement":
        share = args.get("minSharePct")
        if not (isinstance(share, int) and not isinstance(share, bool) and 1 <= share <= 100):
            return ["states no minSharePct between 1 and 100"]
        return []
    if handler != "pim-edit-layout":
        return []
    aspect = args.get("aspect")
    if aspect not in EDIT_LAYOUT_ASPECTS:
        return [f"has unknown edit-layout aspect {aspect!r}"]
    faults = []
    if aspect == "tabs-per-family" and not positive("maxTabs"):
        faults.append("states no maxTabs")
    if aspect == "scannable" and not (positive("maxEditorsPerGroup") and positive("maxEditorsPerTab")):
        faults.append("states no maxEditorsPerGroup and maxEditorsPerTab")
    if aspect == "names" and not (args.get("bannedNames") or args.get("bannedPatterns")):
        faults.append("lists no banned name or pattern")
    return faults


def validate_ledgers(repo: Path) -> list[str]:
    assets = repo / "skills/dw-demo-ledger/assets"
    if not assets.exists():
        return []
    errors, schema_jobs = [], []

    def error(path, message):
        errors.append(f"{path.relative_to(repo).as_posix()}: {message}")

    def read(path, schema=None):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if schema:
                schema_jobs.append({"path": str(path), "schema": str(assets / schema)})
            return data
        except (OSError, ValueError) as exc:
            error(path, f"unreadable JSON ({exc})")
            return None

    handlers = read(assets / "handlers.json") or {}
    for manifest in sorted((assets / "releases").glob("*/manifest.json")):
        root = manifest.parent
        meta = read(manifest) or {}
        if meta.get("functionsGlob") != "functions/*.json" or meta.get("coverageGlob") != "coverage/*.json":
            error(manifest, "expected functions/*.json and coverage/*.json discovery patterns")
        functions, checks, referenced = {}, {}, set()

        def snapshot_path(relative):
            path = (root / relative.replace("\\", "/")).resolve()
            if not path.is_relative_to(root.resolve()):
                raise ValueError("probe path escapes snapshot")
            return path

        for file in sorted((root / "functions").glob("*.json")):
            area = read(file, "ledger.schema.json") or {}
            if area.get("area") != file.stem:
                error(file, "area differs from filename")
            for f in area.get("functions", []):
                if not isinstance(f, dict):
                    error(file, "function must be an object")
                    continue
                fid = f.get("id", "")
                if fid in functions:
                    error(file, f"duplicate function id {fid}")
                functions[fid] = f
                if f.get("area") != file.stem or not fid.startswith(file.stem + "."):
                    error(file, f"function area/namespace mismatch {fid}")
                paths = list(f.get("checks", []))
                paths += [x["probe"] for x in f.get("notApplicable", []) if isinstance(x, dict) and x.get("probe")]
                paths += [x["probe"] for x in f.get("requires", []) if isinstance(x, dict) and x.get("probe")]
                for relative in paths:
                    try:
                        path = snapshot_path(relative)
                    except (ValueError, TypeError, AttributeError):
                        error(file, f"invalid probe path {relative}")
                        continue
                    if path in referenced:
                        if relative in f.get("checks", []):
                            error(file, f"probe referenced more than once {relative}")
                        continue
                    referenced.add(path)
                    check = read(path, "check.schema.json") or {}
                    cid = check.get("id", "")
                    if cid in checks:
                        error(path, f"duplicate check id {cid}")
                    checks[cid] = check
                    if check.get("functionId") != fid:
                        error(path, f"probe owner differs from {fid}")
                    binding_ids = set()
                    for binding in check.get("bindings", []):
                        if not isinstance(binding, dict):
                            error(path, "binding must be an object")
                            continue
                        if binding.get("id") in binding_ids:
                            error(path, "duplicate binding id")
                        binding_ids.add(binding.get("id"))
                        if binding.get("surface") == "sql" and binding.get("localOnly") is not True:
                            error(path, "SQL binding must declare localOnly:true")
                        if binding.get("status") == "implemented":
                            allowed = handlers.get(binding.get("handler"))
                            if not allowed or binding.get("surface") not in allowed:
                                error(path, f"implemented handler/surface not allowlisted: {binding.get('handler')}")
                            if binding.get("surface") == "sql" and binding.get("handler") in ("sql-scalar", "sql-offenders") and not binding.get("query"):
                                error(path, "implemented SQL scalar/offenders binding needs a query")
                            for fault in layout_argument_faults(binding.get("handler"), binding.get("arguments")):
                                error(path, f"{binding.get('handler')} binding {fault}")
        for path in (root / "probes").glob("**/*.json"):
            if path.resolve() not in referenced:
                error(path, "orphan probe is not referenced by a function")
        for fid, f in functions.items():
            for req in f.get("requires", []):
                rid = req.get("id", "")
                if req.get("kind") == "capability" and re.fullmatch(r"[a-z][a-z0-9.-]*", rid) and rid not in functions:
                    error(manifest, f"{fid}: requires unknown function {rid}")
        for file in sorted((root / "coverage").glob("*.json")):
            coverage = read(file, "coverage.schema.json") or {}
            if coverage.get("area") != file.stem or not (root / "functions" / file.name).is_file():
                error(file, "coverage area must match its function-area file")
            for claim in coverage.get("claims", []):
                if not isinstance(claim, dict):
                    error(file, "coverage claim must be an object")
                    continue
                for key in ("functionId", "duplicateOf"):
                    if key in claim and claim[key] not in functions:
                        error(file, f"coverage {key} does not resolve: {claim[key]}")

    # One process validates all schemas, never one process per probe. Paths travel
    # as JSON data on stdin, not as executable command text.
    command = r'''
$ErrorActionPreference='Stop'
$jobs=[Console]::In.ReadToEnd()|ConvertFrom-Json
$failures=@(foreach($job in $jobs){
    try {
        $valid=Test-Json -Json (Get-Content -LiteralPath $job.path -Raw) -SchemaFile $job.schema -ErrorAction Stop
        if(-not $valid){$job.path+': schema validation failed'}
    } catch { $job.path+': schema validation failed: '+$_.Exception.Message }
})
ConvertTo-Json -InputObject $failures -Compress
'''
    try:
        proc = subprocess.run(["pwsh", "-NoProfile", "-NonInteractive", "-Command", command],
                              input=json.dumps(schema_jobs), text=True, capture_output=True, timeout=120)
        if proc.returncode:
            errors.append("ledger schema validation failed to execute in PowerShell 7")
        else:
            errors.extend(json.loads(proc.stdout))
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        errors.append(f"ledger schema validation requires PowerShell 7 Test-Json ({exc})")
    return errors
