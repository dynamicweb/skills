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


PROFILE_KEYS = {"op", "value", "minimumSubjects"}
TEMPLATE_PROVES = "satisfies the selected profile assertion"


def binding_faults(binding, kind, registry, assertion=None) -> list[str]:
    """What an implemented binding must state before the runner may execute it. The registry
    (assets/handlers.json) is the same one the runner reads; nothing here is inferred from a name."""
    handler, surface = binding.get("handler"), binding.get("surface")
    entry = (registry.get("handlers") or {}).get(handler)
    if not isinstance(entry, dict) or surface not in entry.get("surfaces", []):
        return [f"implemented handler/surface not allowlisted: {handler}"]
    faults = []
    args = binding.get("arguments") if isinstance(binding.get("arguments"), dict) else {}
    operation = binding.get("operation")
    if kind not in entry.get("assertions", []):
        faults.append(f"assertion kind {kind} does not fit handler {handler}")
    if surface == "mcp":
        tools = registry.get("mcpReadTools", [])
        if not operation:
            faults.append("MCP binding names no operation")
        for tool in [operation, *(binding.get("requiredTools") or [])]:
            if tool and tool not in tools:
                faults.append(f"MCP tool is not an allowlisted read tool: {tool}")
    if surface == "admin-api":
        if not operation:
            faults.append("Admin binding names no operation")
        elif operation not in registry.get("adminReadQueries", []):
            faults.append(f"Admin operation is not an allowlisted read query: {operation}")
    if surface == "dwapi":
        # A delivery read is one anonymous GET; some GET routes switch a profile or issue a token, so the route is listed.
        if not operation:
            faults.append("delivery binding names no operation")
        elif operation not in registry.get("dwapiReadRoutes", []):
            faults.append(f"delivery route is not an allowlisted read route: {operation}")
    if handler in ("admin-query-count", "dwapi-count") and not (binding.get("projection") or {}).get("rowsPath"):
        faults.append(f"{handler} needs projection.rowsPath")
    if handler == "admin-feature-flag" and not args.get("featureTypeName"):
        faults.append("admin-feature-flag needs arguments.featureTypeName")
    if handler == "files-count" and not (binding.get("path") or (args.get("folder") and args.get("filter"))):
        faults.append("files-count needs a path, or arguments.folder with arguments.filter")
    if handler == "settings-value" and not args.get("key"):
        faults.append("settings-value needs arguments.key")
    if handler in ("sql-scalar", "sql-offenders") and not binding.get("query"):
        faults.append("implemented SQL scalar/offenders binding needs a query")
    if binding.get("subjectsQuery") and handler != "sql-offenders":
        faults.append("subjectsQuery belongs to an sql-offenders binding only")
    # Zero offenders over zero subjects proves nothing; a minimum needs the subjects counted.
    if handler == "sql-offenders" and "minimumSubjects" in (assertion or {}) and not binding.get("subjectsQuery"):
        faults.append("sql-offenders with minimumSubjects needs a subjectsQuery")
    return faults + [f"{handler} binding {fault}" for fault in layout_argument_faults(handler, binding.get("arguments"))]


def requirement_cycles(functions) -> list[str]:
    """A capability requirement that names a function holds when that function's checks pass, and a
    ground may cite a function the same way (requiresFunction). A circle can never be established."""
    edges = {}
    for fid, f in functions.items():
        targets = [r.get("id") for r in f.get("requires", []) if isinstance(r, dict) and r.get("kind") == "capability"]
        targets += [g.get("requiresFunction") for g in f.get("notApplicable", []) if isinstance(g, dict)]
        edges[fid] = sorted({t for t in targets if isinstance(t, str) and t in functions})
    faults, done = [], set()

    def visit(fid, path):
        if fid in path:
            circle = path[path.index(fid):] + [fid]
            start = circle.index(min(circle[:-1]))
            circle = circle[start:-1] + circle[:start] + [circle[start]]
            faults.append("circular function requirement: " + " -> ".join(circle))
            return
        if fid in done:
            return
        for target in edges[fid]:
            visit(target, path + [fid])
        done.add(fid)

    for fid in sorted(edges):
        visit(fid, [])
    return sorted(set(faults))


def validate_ledgers(repo: Path) -> list[str]:
    assets = repo / "skills/dw-demo-ledger/assets"
    if not assets.exists():
        return []
    errors, schema_jobs, sql_jobs = [], [], []

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

    registry = read(assets / "handlers.json") or {}
    if not isinstance(registry.get("handlers"), dict):
        error(assets / "handlers.json", "expected handlers, mcpReadTools and adminReadQueries")
    for file in sorted((assets / "profiles").glob("*.json")):
        profile = read(file) or {}
        for cid, overrides in (profile.get("expectations") or {}).items():
            extra = sorted(set(overrides) - PROFILE_KEYS) if isinstance(overrides, dict) else ["(not an object)"]
            if extra:
                error(file, f"profile may change only op, value and minimumSubjects: {cid} states {', '.join(extra)}")
    for manifest in sorted((assets / "releases").glob("*/manifest.json")):
        root = manifest.parent
        meta = read(manifest) or {}
        if meta.get("schema") != 1 or not isinstance(meta.get("dwVersion"), str) or not meta.get("dwVersion"):
            error(manifest, "manifest needs schema 1 and a dwVersion")
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
                    # A PASS is audited against its claim; the template text states none.
                    if TEMPLATE_PROVES in ((check.get("intent") or {}).get("proves") or ""):
                        error(path, "intent.proves is the template text; state what the check proves")
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
                        for key in ("query", "subjectsQuery"):
                            if isinstance(binding.get(key), str):
                                sql_jobs.append({"path": path.relative_to(repo).as_posix(), "query": binding[key]})
                        if binding.get("status") == "implemented":
                            kind = (check.get("assertion") or {}).get("kind")
                            for fault in binding_faults(binding, kind, registry, check.get("assertion")):
                                error(path, fault)
        for path in (root / "probes").glob("**/*.json"):
            if path.resolve() not in referenced:
                error(path, "orphan probe is not referenced by a function")
        # Evidence, deltas and migration maps are hashed into the snapshot digest; each must at least parse.
        for path in sorted(root.glob("**/*.json")):
            if path.relative_to(root).parts[0] not in ("functions", "probes", "coverage") and path != manifest:
                read(path)
        for fid, f in functions.items():
            for req in f.get("requires", []):
                rid = req.get("id", "")
                # A description is not a fact id: no discovery can ever match it, so the check stays UNVERIFIED.
                if re.search(r"\s", rid):
                    error(manifest, f"{fid}: requirement id is a description, not a fact id: {rid}")
                if req.get("kind") == "capability" and re.fullmatch(r"[a-z][a-z0-9.-]*", rid) and rid not in functions:
                    error(manifest, f"{fid}: requires unknown function {rid}")
            primary = set()
            for relative in f.get("checks", []):
                try:
                    primary.add(json.loads(snapshot_path(relative).read_text(encoding="utf-8")).get("id"))
                except (OSError, ValueError, TypeError, AttributeError):
                    continue
            for ground in f.get("notApplicable", []):
                cited = ground.get("requiresFunction") if isinstance(ground, dict) else None
                if cited is not None and (cited not in functions or cited == fid):
                    error(manifest, f"{fid}: ground {ground.get('id')} cites unknown function {cited}")
                # A ground that names checks rules out only those; each must be a check the function lists.
                scoped = ground.get("checks") if isinstance(ground, dict) else None
                for cid in scoped or []:
                    if cid not in primary:
                        error(manifest, f"{fid}: ground {ground.get('id')} names {cid}, which is not a check of this function")
        for fault in requirement_cycles(functions):
            error(manifest, fault)
        claimed = set()
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
                    elif key in claim:
                        claimed.add(claim[key])
        # Every function carries a claim; one without a check says so ("no check yet").
        for fid in sorted(set(functions) - claimed):
            error(manifest, f"{fid}: function has no coverage claim")

    # One process validates all schemas and every SQL text, never one process per probe. Paths
    # and queries travel as JSON data on stdin, not as executable command text. The SQL check is
    # the runner's own guard (Assert-LedgerSelect), so the validator and the runner cannot drift.
    guard = repo / "skills/dw-demo-ledger/scripts/Ledger.Sql.ps1"
    if not guard.is_file():
        guard = Path(__file__).resolve().parents[1] / "skills/dw-demo-ledger/scripts/Ledger.Sql.ps1"
    command = r'''
$ErrorActionPreference='Stop'
$work=[Console]::In.ReadToEnd()|ConvertFrom-Json
. $work.guard
$failures=@(foreach($job in $work.schemas){
    try {
        $valid=Test-Json -Json (Get-Content -LiteralPath $job.path -Raw) -SchemaFile $job.schema -ErrorAction Stop
        if(-not $valid){$job.path+': schema validation failed'}
    } catch { $job.path+': schema validation failed: '+$_.Exception.Message }
}
foreach($job in $work.sql){
    try {Assert-LedgerSelect $job.query} catch {$job.path+': SQL binding is not a single read-only SELECT statement'}
})
ConvertTo-Json -InputObject $failures -Compress
'''
    try:
        work = {"guard": str(guard), "schemas": schema_jobs, "sql": sql_jobs}
        proc = subprocess.run(["pwsh", "-NoProfile", "-NonInteractive", "-Command", command],
                              input=json.dumps(work), text=True, capture_output=True, timeout=120)
        if proc.returncode:
            errors.append("ledger schema validation failed to execute in PowerShell 7")
        else:
            errors.extend(json.loads(proc.stdout))
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        errors.append(f"ledger schema validation requires PowerShell 7 Test-Json ({exc})")
    return errors
