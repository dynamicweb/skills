"""Read-only recipe validation, called by validate-skills.py beside the ledger validation.

A recipe (skills/dw-demo-ledger/assets/recipes/<area>/<id>.json) is checked against its draft-7
schema with PowerShell 7 Test-Json, and against the repository: the functions it delivers and the
ledger checks it names resolve in a release snapshot, every operation is on the allowlists in
assets/handlers.json and every MCP name in the tool registry, SQL is a local, parameterised,
single SELECT (the ledger's own guard), every token resolves against the input schema or an
earlier step, the declared MCP-only and hosted modes agree with the bindings, and no string holds
a host, a machine path or a credential. No target connection, no third-party Python package.
"""
import json
import re
import subprocess
from pathlib import Path

TOKEN_RE = re.compile(r"\{([^{}]+)\}")
DEFAULT_PATH_RE = re.compile(r"^(input|item|parent|build)(\.[A-Za-z0-9_]+(\[(\d+|\*)\])?)+$")
STEP_TOKEN_RE = re.compile(r"^step\.([a-z][a-z0-9-]*)(?:\[((?:[^\[\]]|\[\*\])+)\])?\.([A-Za-z0-9_.]+)$")
FORBIDDEN = (
    (re.compile(r"(?i)\b[a-z][a-z0-9+.-]*://"), "a URL or host"),
    (re.compile(r"(?i)\b(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?\b"), "a host or address"),
    (re.compile(r"(?i)\b[a-z]:\\|^\\\\|^(/home/|/Users/|~/)"), "a machine path"),
    (re.compile(r"(?i)\b(claude|mcp)\.[0-9a-f]{40,}|Bearer\s+\S{20,}"), "a token-shaped secret"),
    (re.compile(r"(?i)truvio"), "a distribution, layer or edition name"),
)
CREDENTIAL_KEYS = re.compile(r"(?i)^(password|pwd|token|apikey|secret)$")
BUILD_KEYS = {"areaId", "defaultLanguage", "pimShop"}


def version_key(text):
    return tuple(int(p) for p in re.findall(r"\d+", text)[:4])


def load_releases(assets, error):
    """{dwVersion: {"functions": {id: function}, "checks": {checkId: functionId}}} from every snapshot."""
    releases = {}
    for manifest in sorted((assets / "releases").glob("*/manifest.json")):
        try:
            version = json.loads(manifest.read_text(encoding="utf-8")).get("dwVersion")
        except ValueError:
            continue
        functions, checks = {}, {}
        for file in sorted((manifest.parent / "functions").glob("*.json")):
            try:
                area = json.loads(file.read_text(encoding="utf-8"))
            except ValueError:
                continue
            for f in area.get("functions", []):
                functions[f.get("id")] = f
                for rel in f.get("checks", []):
                    try:
                        check = json.loads((manifest.parent / rel).read_text(encoding="utf-8"))
                        checks[check.get("id")] = f.get("id")
                    except (OSError, ValueError):
                        continue
        if isinstance(version, str):
            releases[version] = {"functions": functions, "checks": checks}
    return releases


def mcp_tool_names(repo):
    index = repo / "scripts/mcp-tools/index.json"
    try:
        current = json.loads(index.read_text(encoding="utf-8"))["current"]
        return set(json.loads((repo / "scripts/mcp-tools" / f"{current}.json").read_text(encoding="utf-8")).get("tools", {}))
    except (OSError, ValueError, KeyError):
        return None


def strings(value, where="$"):
    if isinstance(value, str):
        yield where, value
    elif isinstance(value, dict):
        for k, v in value.items():
            yield from strings(v, f"{where}.{k}")
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from strings(v, f"{where}[{i}]")


def forbidden_faults(value, where="$"):
    faults = []
    for path, text in strings(value, where):
        for pattern, what in FORBIDDEN:
            if pattern.search(text):
                faults.append(f"{path} holds {what}")
                break
    stack = [(where, value)]
    while stack:
        path, node = stack.pop()
        if isinstance(node, dict):
            for k, v in node.items():
                if CREDENTIAL_KEYS.match(k) and isinstance(v, str) and not v.startswith("{secret."):
                    faults.append(f"{path}.{k} holds a credential literal")
                stack.append((f"{path}.{k}", v))
        elif isinstance(node, list):
            stack.extend((f"{path}[{i}]", v) for i, v in enumerate(node))
    return faults


def schema_at(schema, path):
    """The sub-schema a dotted input path names, or None. An object without declared properties
    (a field map) accepts any member below it."""
    node = schema
    for part in [p for p in path.split(".") if p]:
        name = part.replace("[*]", "")
        if not isinstance(node, dict):
            return None
        props = node.get("properties")
        if isinstance(props, dict) and name in props:
            node = props[name]
        elif isinstance(node.get("additionalProperties"), dict):
            node = node["additionalProperties"]
        else:
            return None
        if part.endswith("[*]"):
            node = node.get("items") if isinstance(node, dict) else None
    return node


def scopes(section_schema, for_each):
    """(item schema, parent schema) for a forEach path."""
    if not for_each:
        return section_schema, None
    parts, node, parent, previous = for_each.split("."), section_schema, None, None
    for part in parts:
        node = schema_at(node, part)
        if node is None:
            return None, None
        if part.endswith("[*]"):
            parent, previous = previous, node
    return node, parent


def produced(step):
    names = set()
    for b in (step.get("find") or {}).get("bindings", []):
        names |= set((b.get("produces") or {}))
    for b in step.get("bindings", []):
        names |= set(((b.get("readBack") or {}).get("produces") or {}))
    return names


def inline_refs(node, definitions):
    """The input schema with each local #/definitions/<name> reference replaced by its definition, so a
    path through a shared definition (an order's lines) resolves."""
    if isinstance(node, dict):
        ref = node.get("$ref")
        if isinstance(ref, str) and ref.startswith("#/definitions/") and ref[14:] in definitions:
            return inline_refs(definitions[ref[14:]], definitions)
        return {k: inline_refs(v, definitions) for k, v in node.items()}
    if isinstance(node, list):
        return [inline_refs(v, definitions) for v in node]
    return node


def conditions(skip_when):
    """A skipWhen as a list of condition objects (one condition, or a list that skips when any holds)."""
    items = skip_when if isinstance(skip_when, list) else [skip_when]
    return [c for c in items if isinstance(c, dict)]


def readable(binding, surfaces):
    return binding.get("status") == "implemented" and binding.get("surface") in surfaces


def step_usable(step, surfaces, write_surfaces):
    """True when the step has an implemented find (if it finds) and an implemented write binding
    whose write and read-back stay on the given surfaces."""
    find = step.get("find")
    if find and not any(readable(b, surfaces) for b in find.get("bindings", [])):
        return False
    if not step.get("bindings"):
        # A lookup step finds and never writes: its find is all it needs.
        return bool(find)
    return any(b.get("status") == "implemented" and b.get("surface") in write_surfaces and ("create" in b or "update" in b)
               and readable(b.get("readBack") or {}, surfaces) for b in step.get("bindings", []))


def validate_recipes(repo: Path) -> list[str]:
    assets = repo / "skills/dw-demo-ledger/assets"
    root = assets / "recipes"
    if not root.exists():
        return []
    errors, schema_jobs, sql_jobs = [], [], []

    def error(path, message):
        errors.append(f"{path.relative_to(repo).as_posix()}: {message}")

    try:
        registry = json.loads((assets / "handlers.json").read_text(encoding="utf-8"))
        input_schema = json.loads((assets / "recipe-input.schema.json").read_text(encoding="utf-8"))
        input_schema = inline_refs(input_schema, input_schema.get("definitions") or {})
    except (OSError, ValueError) as exc:
        return [f"recipe validation cannot read handlers.json or recipe-input.schema.json ({exc})"]
    releases = load_releases(assets, error)
    newest = max(releases, key=version_key) if releases else None
    tools = mcp_tool_names(repo)
    build_schema = (input_schema.get("properties") or {}).get("build") or {}
    for example in sorted(assets.glob("recipe-input*.json")):
        if example.name != "recipe-input.schema.json":
            schema_jobs.append({"path": str(example), "schema": str(assets / "recipe-input.schema.json")})
            try:
                for fault in forbidden_faults(json.loads(example.read_text(encoding="utf-8"))):
                    error(example, fault)
            except ValueError as exc:
                error(example, f"unreadable JSON ({exc})")
    seen = {}
    for file in sorted(root.glob("*/*.json")):
        try:
            doc = json.loads(file.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            error(file, f"unreadable JSON ({exc})")
            continue
        schema_jobs.append({"path": str(file), "schema": str(assets / "recipe.schema.json")})
        if not isinstance(doc, dict):
            continue
        rid = doc.get("id", "")
        if rid in seen:
            error(file, f"duplicate recipe id {rid} (also {seen[rid]})")
        seen[rid] = file.name
        if file.stem != rid or file.parent.name != rid.split(".")[0]:
            error(file, f"recipe {rid} must live at recipes/{rid.split('.')[0]}/{rid}.json")
        for fault in forbidden_faults(doc):
            error(file, fault)
        functions = doc.get("functions") or []
        if rid not in functions:
            error(file, f"the recipe id {rid} must be its primary ledger function and be listed in functions")
        proven = [p.get("dwVersion") for p in doc.get("provenOn") or [] if isinstance(p, dict)]
        candidates = [v for v in proven if v in releases] if proven else ([newest] if newest else [])
        for v in proven:
            if v not in releases:
                error(file, f"provenOn names {v}, which has no release snapshot")
        known = {}
        for v in candidates:
            known.update(releases[v]["functions"])
        checks = {}
        for v in candidates:
            checks.update(releases[v]["checks"])
        for fid in functions:
            if fid not in known:
                error(file, f"function {fid} is not in {'the provenOn releases' if proven else 'the newest release snapshot'}")
        skill = doc.get("skill", "")
        if not (repo / "skills" / skill / "SKILL.md").is_file():
            error(file, f"skill {skill} does not exist")
        elif rid in known and known[rid].get("skill") != skill:
            error(file, f"skill {skill} is not the owner of {rid} ({known[rid].get('skill')})")
        for cid in (doc.get("verify") or {}).get("checkIds", []):
            if checks.get(cid) not in functions:
                error(file, f"ledger check {cid} is not a check of the recipe's functions")
        section_name = (doc.get("inputs") or {}).get("section", "")
        section = (input_schema.get("properties") or {}).get(section_name)
        if not isinstance(section, dict):
            error(file, f"input section {section_name} is not in recipe-input.schema.json")
            section = {}
        for path in (doc.get("inputs") or {}).get("required", []):
            if schema_at(section, path) is None:
                error(file, f"required input {path} is not in section {section_name}")
        steps = doc.get("steps") or []
        step_ids, earlier = {}, []
        for step in steps:
            if step.get("id") in step_ids:
                error(file, f"duplicate step id {step.get('id')}")
            step_ids[step.get("id")] = produced(step)
        for step in steps:
            sid = step.get("id")
            item, parent = scopes(section, step.get("forEach"))
            if step.get("forEach") and item is None:
                error(file, f"step {sid}: forEach {step.get('forEach')} is not in section {section_name}")
            if not step.get("bindings") and not step.get("find"):
                error(file, f"step {sid}: a step without write bindings is a lookup and needs a find")
            after = (step.get("after") or {}).get("step")
            if after and after not in earlier:
                error(file, f"step {sid}: after names {after}, which is not an earlier step")

            def check_tokens(value, where, allow_secret=False, allow_found=False):
                for path, text in strings(value, where):
                    for body in TOKEN_RE.findall(text):
                        fault = token_fault(body, allow_secret, allow_found)
                        if fault:
                            error(file, f"step {sid} {path}: token {{{body}}} {fault}")

            def token_fault(body, allow_secret, allow_found):
                for prefix in ("text:", "base64:", "bytes:"):
                    if body.startswith(prefix):
                        body = body[len(prefix):]
                        break
                path, _, default = body.partition("|")
                if default:
                    try:
                        json.loads(default)
                    except ValueError:
                        if not DEFAULT_PATH_RE.match(default):
                            return "has a default that is neither a JSON literal nor an input path"
                        if root_fault(default):
                            return root_fault(default)
                if path.startswith("secret."):
                    return None if allow_secret else "is a secret outside a write or read-back argument"
                m = STEP_TOKEN_RE.match(path)
                if m:
                    target, key, field = m.groups()
                    if target not in step_ids or (target not in earlier and target != sid):
                        return f"names step {target}, which is not this or an earlier step"
                    if field not in step_ids[target]:
                        return f"names {field}, which step {target} does not produce"
                    for kp in (key or "").split(","):
                        if kp and root_fault(kp.strip()):
                            return root_fault(kp.strip())
                    return None
                return root_fault(path, allow_found)

            def root_fault(path, allow_found=False):
                head, _, rest = path.partition(".")
                if head == "found":
                    return None if allow_found else "reads found outside an update"
                if head == "build":
                    return None if rest in BUILD_KEYS and rest in (build_schema.get("properties") or {}) else f"names an unknown build value {rest}"
                base = {"input": section, "item": item, "parent": parent}.get(head)
                if head not in ("input", "item", "parent"):
                    return "has an unknown root"
                if base is None or schema_at(base, rest) is None:
                    return f"does not resolve in the input schema ({head}.{rest})"
                return None

            check_tokens(step.get("key"), "key")
            for cond in conditions(step.get("skipWhen")):
                if root_fault(cond.get("path", "")):
                    error(file, f"step {sid} skipWhen: {root_fault(cond.get('path', ''))}")
                for value in (cond.get(k) for k in ("equals", "notEquals", "contains") if k in cond):
                    check_tokens(value, "skipWhen")
            for b in (step.get("find") or {}).get("bindings", []):
                check_binding(b, "read", f"step {sid} find", file, error, registry, tools, sql_jobs)
                check_tokens({k: b.get(k) for k in ("arguments", "match", "compare", "compareMap", "parameters")}, "find")
            for b in step.get("bindings", []):
                check_binding(b, "write", f"step {sid} {b.get('id')}", file, error, registry, tools, sql_jobs)
                if "create" in b:
                    check_tokens(b["create"].get("arguments"), "create", allow_secret=True)
                if "update" in b:
                    check_tokens(b["update"].get("arguments"), "update", allow_secret=True, allow_found=True)
                rb = b.get("readBack")
                if rb:
                    check_binding(rb, "read", f"step {sid} {b.get('id')} readBack", file, error, registry, tools, sql_jobs)
                    check_tokens({k: rb.get(k) for k in ("arguments", "parameters")}, "readBack", allow_secret=True)
                    check_tokens({k: rb.get(k) for k in ("match", "expect", "expectMap")}, "readBack")
            earlier.append(sid)
        for probe in (doc.get("verify") or {}).get("probes", []):
            pid = probe.get("id")
            item, parent = scopes(section, probe.get("forEach"))
            if probe.get("forEach") and item is None:
                error(file, f"probe {pid}: forEach {probe.get('forEach')} is not in section {section_name}")
            for cond in conditions(probe.get("skipWhen")):
                head, _, rest = (cond.get("path") or "").partition(".")
                base = {"input": section, "item": item, "parent": parent}.get(head)
                if base is None or schema_at(base, rest) is None:
                    error(file, f"probe {pid} skipWhen: {cond.get('path')} does not resolve in the input schema")
            for b in probe.get("bindings", []):
                check_binding(b, "probe", f"probe {pid}", file, error, registry, tools, sql_jobs)
                for path, text in strings({k: b.get(k) for k in ("arguments", "match", "parameters", "assert", "signIn")}, f"probe {pid}"):
                    for body in TOKEN_RE.findall(text):
                        if body.startswith("secret."):
                            in_sign_in = (b.get("handler") == "dwapi-sign-in" and path.startswith(f"probe {pid}.arguments")) or \
                                (b.get("handler") == "dwapi-signed-in-get" and path.startswith(f"probe {pid}.signIn"))
                            if not in_sign_in:
                                error(file, f"{path}: token {{{body}}} is a secret outside a sign-in probe's arguments")
                            continue
                        m = STEP_TOKEN_RE.match(body.split("|")[0].removeprefix("text:"))
                        if m and (m.group(1) not in step_ids or m.group(3) not in step_ids[m.group(1)]):
                            error(file, f"{path}: token {{{body}}} names a value no step produces")
                        elif not m:
                            head, _, rest = body.split("|")[0].removeprefix("text:").partition(".")
                            base = {"input": section, "item": item, "parent": parent}.get(head)
                            if head == "build":
                                if rest not in BUILD_KEYS:
                                    error(file, f"{path}: token {{{body}}} names an unknown build value")
                            elif base is None or schema_at(base, rest) is None:
                                error(file, f"{path}: token {{{body}}} does not resolve in the input schema")
        modes = doc.get("modes") or {}
        mcp_only = bool(steps) and all(step_usable(s, {"mcp"}, {"mcp"}) for s in steps)
        hosted = bool(steps) and all(step_usable(s, {"mcp", "admin-api", "dwapi"}, {"mcp", "admin-api"}) for s in steps)
        if (modes.get("mcpOnly") or {}).get("usable") is not mcp_only:
            error(file, f"modes.mcpOnly.usable must be {str(mcp_only).lower()}: computed from the implemented MCP find, write and read-back bindings of every step")
        if (modes.get("hosted") or {}).get("usable") is not hosted:
            error(file, f"modes.hosted.usable must be {str(hosted).lower()}: computed from the implemented non-SQL find, write and read-back bindings of every step")
    return errors + run_powershell(repo, schema_jobs, sql_jobs)


def check_binding(b, kind, where, file, error, registry, tools, sql_jobs):
    """Allowlists, registry names, SQL shape and the members an implemented binding needs."""
    surface, status = b.get("surface"), b.get("status")
    operation = b.get("operation") or (b.get("create") or {}).get("operation") or (b.get("update") or {}).get("operation")
    ops = [o for o in [b.get("operation"), (b.get("create") or {}).get("operation"), (b.get("update") or {}).get("operation")] if o]
    if surface == "mcp" and tools is not None:
        for op in ops:
            if op not in tools:
                error(file, f"{where}: {op} is not in the MCP tool registry")
    if surface == "sql":
        if kind == "write":
            error(file, f"{where}: SQL never writes in a recipe")
        query = b.get("query") or ""
        sql_jobs.append({"path": file.as_posix(), "query": query})
        named = set(re.findall(r"@([A-Za-z][A-Za-z0-9]*)", query))
        if named != set((b.get("parameters") or {})):
            error(file, f"{where}: SQL parameters {sorted(b.get('parameters') or {})} differ from the query's {sorted(named)}")
        if TOKEN_RE.search(query):
            error(file, f"{where}: a token inside SQL text; pass it as a parameter")
    if status != "implemented":
        return
    if kind == "write":
        lists = {"mcp": registry.get("recipeWriteTools", []), "admin-api": registry.get("recipeAdminCommands", [])}
        for op in ops:
            if op not in lists.get(surface, []):
                error(file, f"{where}: {surface} {op} is not on the recipe write allowlist")
        rb = b.get("readBack") or {}
        if rb.get("status") != "implemented":
            error(file, f"{where}: an implemented write needs an implemented read-back")
        return
    if surface == "mcp" and operation not in registry.get("mcpReadTools", []) + registry.get("recipeRenderedReadTools", []):
        error(file, f"{where}: MCP {operation} is not on mcpReadTools")
    if surface == "admin-api" and operation not in registry.get("adminReadQueries", []):
        error(file, f"{where}: Management API {operation} is not on adminReadQueries")
    if surface == "dwapi":
        handler = b.get("handler")
        routes = {"dwapi-get": registry.get("dwapiReadRoutes", []), "dwapi-signed-in-get": registry.get("recipeSignedInReadRoutes", [])}.get(handler, registry.get("dwapiSignInRoutes", []))
        if operation not in routes:
            error(file, f"{where}: delivery route {operation} is not on the allowlist for {handler}")
        if handler == "dwapi-persona-sign-in" and (b.get("arguments") or {}).get("readAs") not in registry.get("dwapiSignedInReadRoutes", []):
            error(file, f"{where}: dwapi-persona-sign-in needs arguments.readAs on dwapiSignedInReadRoutes")
        if handler == "dwapi-persona-sign-in" and kind != "probe":
            error(file, f"{where}: dwapi-persona-sign-in is a probe handler")
    if surface != "sql" and not b.get("rows") and b.get("handler") != "dwapi-persona-sign-in":
        error(file, f"{where}: an implemented read names its rows ('$' for the response itself)")
    if kind == "probe" and not b.get("assert"):
        error(file, f"{where}: an implemented probe binding needs an assert")
    if kind == "probe" and (b.get("assert") or {}).get("kind") in ("equals", "contains") and not (b.get("assert") or {}).get("path"):
        error(file, f"{where}: an equals or contains assert needs a path")


def run_powershell(repo, schema_jobs, sql_jobs):
    """One PowerShell process for every schema and every SQL text, using the runner's own guard."""
    if not schema_jobs and not sql_jobs:
        return []
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
        if(-not $valid){$job.path+': recipe schema validation failed'}
    } catch { $job.path+': recipe schema validation failed: '+$_.Exception.Message }
}
foreach($job in $work.sql){
    try {Assert-LedgerSelect $job.query} catch {$job.path+': recipe SQL is not a single read-only SELECT statement'}
})
ConvertTo-Json -InputObject $failures -Compress
'''
    try:
        work = {"guard": str(guard), "schemas": schema_jobs, "sql": sql_jobs}
        proc = subprocess.run(["pwsh", "-NoProfile", "-NonInteractive", "-Command", command],
                              input=json.dumps(work), text=True, capture_output=True, timeout=120)
        if proc.returncode:
            return ["recipe schema validation failed to execute in PowerShell 7"]
        found = json.loads(proc.stdout)
        out = []
        for line in found:
            try:
                head, _, rest = line.partition(": ")
                out.append(f"{Path(head).resolve().relative_to(repo.resolve()).as_posix()}: {rest}")
            except ValueError:
                out.append(line)
        return out
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        return [f"recipe schema validation requires PowerShell 7 Test-Json ({exc})"]
