# Ledger contract

The Truvio Commerce (powered by Dynamicweb) ledger describes platform functions independently of the build that uses them. Schema version 1 uses JSON Schema draft 7. All paths below are relative to the selected release directory unless stated otherwise.

## Files and authorship

The manifest declares an exact `dwVersion`, candidate/measured status, `functionsGlob: functions/*.json` and `coverageGlob: coverage/*.json`. Each area owns one file `{schema:1, area, functions:[...]}` matching `assets/ledger.schema.json`. Manual claims in `coverage/<area>.json` match `assets/coverage.schema.json` and name a function, a duplicate function or an exclusion with a reason. Missing source hashes remain a provenance gap, not an invented hash. The migrated PIM inventory retains its migration map; it does not yet have a manual coverage map. A function has a stable namespaced id, area, name, owning skill, status, requires, inputs, checks, notApplicable and sources. No per-entry `since` is required. `status` is candidate, documented or measured; source evidence does not become measured evidence by being copied.

Each `checks` element is a relative path such as `probes/pim/workspaces.completeness-level.json`. It points to one document matching `assets/check.schema.json`, not an inline check or merely an id. A check id is globally unique and its `functionId` must name its owner. Paths must remain inside the snapshot. Do not embed machine paths, hosts, customer names or credentials.

Each area author writes only its own function file and probe directory. Do not edit the manifest or schema to add an area: the functions glob discovers it. Do not claim unsupported versions. Matrix fields are excluded from the initial snapshot until their release boundary is established separately.

## Check intent and bindings

`intent` contains `proves`, `level` and `scope`. Levels are supported (capability exists), configured (settings exist), applied (declared data uses it), behavioural (observed outcome), and stored-integrity (raw representation). Levels are different claims, not interchangeable scores.

`assertion.kind` is scalar, offenders, attributes, families or widget-queries. Scalar assertions use op eq/ge/le and value. Offenders pass on zero offenders only after complete enumeration; handlers enforce nonempty expected scope where the claim needs it. Domain assertions may add aspect and minimumSubjects. Breadth profiles override expectations explicitly by check id; they never change the check's observation semantics. A profile entry may state `op`, `value` and `minimumSubjects` only: any other key (`kind`, `aspect`) makes the check ERROR, and the repository validator refuses the profile. The assertion kind must be one the binding's handler reports (`assertions` in `assets/handlers.json`): a scalar handler reports no offenders, so an offenders assertion over it is refused by the validator and is ERROR in the runner.

A binding contains id, surface, status and handler. Surfaces are mcp, admin-api, dwapi, file and sql. `status: implemented` means the runner has that exact handler; it is not a statement that the binding is measured on every host. `status: planned` requires reason and cannot execute. Put a discovered tool/query in operation, arguments in an object, SQL SELECT in query, and a relative file pattern in path. SQL always requires localOnly:true. Optional requiredTools/requiredPaths declare additional reads. A handler name never runs arbitrary code: the runner dispatches a fixed allowlist. The same holds for what a binding names: an implemented MCP binding's `operation` and `requiredTools` must be on `mcpReadTools` in `assets/handlers.json`, and an implemented Admin binding's `operation` on `adminReadQueries`. The validator refuses anything else, and the runner refuses an MCP tool off the list before the call, even when the target lists it. Promoting a planned binding to a new read tool is an edit to that list.

**Area authors:** until a handler is implemented and tested, use status:planned with an honest reason. Suggested operation names are not measured bindings. The implemented handler allowlist is `handlers` in `assets/handlers.json` (surfaces and assertion kinds per handler), checked by the runner and repository validator:

- MCP: `mcp-count`, `mcp-files-count`, `mcp-workspace-count`, `mcp-workspace-empty`, `mcp-workspace-completeness`, `mcp-workflow-states`, `mcp-workflow-transitions`, `mcp-completion-rules`, `mcp-dashboard-count`, `mcp-field-types`, `mcp-field-text-share`, `mcp-multiselect`.
- Admin API: `admin-query-count`, requiring a successful authenticated read and a discovered named GET query. A public descriptor alone never permits a permission count. `admin-feature-flag` reads one feature's state from the complete `FeaturesAll` enumeration by `arguments.featureTypeName`; an unknown feature is UNVERIFIED.
- Local files: `files-count`, `settings-value`, `xml-count`.
- Local SQL: `sql-scalar`, `sql-offenders`, `pim-attributes`, `pim-families`, `pim-widget-queries`, `pim-edit-layout`, `pim-field-placement`, `pim-matrix` ([matrix-fields.md](matrix-fields.md)), `cpq-structured-read` ([cpq-observations.md](cpq-observations.md)).

A SQL `query` is one SELECT statement. The guard works on the executable tokens (string literals and delimited identifiers set aside): it refuses statement keywords, comments, `;`, a second SELECT outside a set operator and unbalanced text, and the repository validator runs the same guard over every probe. Read-only is also a property of the execution: every local SQL read runs inside a transaction that is always rolled back.

`pim-edit-layout` and `pim-field-placement` carry no query: they read fixed tables once per run and take their aspect and limits from `arguments` ([edit-layout.md](edit-layout.md)). The runner and the repository validator refuse such a binding without the limits its rule needs.

`mcp-provider-types` is still planned, not implemented. An implemented handler does not make every proposed binding equivalent: the PIM field projection bindings remain planned where scope differs or a required DTO field is absent.

`mcp-count` may declare `projection.filter: {field:"isDefault", op:"equals", value:true}`. Operators are typed `equals` and case-sensitive literal text `contains`; dotted field paths are supported. A missing field or incomplete paged collection is UNVERIFIED. It never counts a page as the full collection. Admin counts additionally require an explicit `projection.rowsPath` (`$` for a root array, otherwise a dotted member path) matching a measured response. Filter values stay separate from API arguments.

MCP and Admin arguments support `{areaId}`, `{lang}` and `{pimShop}` from build `areaId`, `defaultLanguage` and `pimShop`. Whole-value substitution preserves the input type; substitution inside text remains text. Undeclared or unknown tokens are UNVERIFIED. No token is evaluated as code or expanded into SQL.

`files-count` takes `arguments.folder` plus `filter`, optionally `includeSubfolders`, or a relative `path` wildcard. Both resolve under the runtime Files root. For example `System/AddIns/Local` means `/Files/System/AddIns/Local`; `Files/Integration/jobs` deliberately means `/Files/Files/Integration/jobs`. A leading virtual `/Files/` in `path` is accepted and removed once. Do not prefix a relative System path with another `Files/`. Wildcards match one path component each; `**` recursion is not supported. `includeSubfolders:true` includes immediate child directories only, preserving migrated scope. Missing roots/folders and denied paths are UNVERIFIED. Path escapes and linked directories are rejected. MCP file counts use explicit virtual paths and the same one-level scope.

`settings-value` reads exactly one local XML file and a literal `arguments.key` such as `/Globalsettings/Settings/Auditing/EnableAuditing`, comparing it with `arguments.equals`. It emits 1 for a match, 0 for a mismatch, never the raw value. Missing keys are UNVERIFIED (no inferred default); duplicate keys are ERROR. Unmeasured setting keys stay planned. `xml-count` takes a local file `path` pattern or folder/filter plus a reviewed `arguments.xpath`, and counts matching nodes across all matching files. It supports job provider/schedule/conditional nodes and repository/index definitions without executing a job or building an index. XML external entities and DTDs are prohibited. The exact selector and binding need evidence before promotion.

MCP comes first when it meets the observation contract, then Management API. Files and /dwapi prove only their specific claims. Local SQL is the optional last binding. A binding unavailable before observation can fall back to another equivalent one. An authorisation refusal (for example an MCP file read outside the add-in's read allowlist) returns no observation, so the runner tries the next implemented binding and names the refused one in the reason. A valid failing observation stays FAIL. A runtime error is recorded, not hidden by retrying different semantics.

A measured scope mismatch with another binding requires investigation and a planned binding until equivalence is established. Category counts cannot stand for event counts; capped search results cannot stand for complete page or paragraph enumeration. Preserve the differing observations in the proof record instead of adjusting thresholds to make them agree.

## Build and lock

Builds match assets/build.schema.json: schema, slug, lock and functions are required. The lock carries full git commit, manifest path, snapshot digest and explicit checkIds. `lock.manifest` is the manifest path relative to the skills repository root, with forward slashes, whatever directory the runner is started from:

```json
"lock": {
  "commit": "<40-character commit of the skills checkout>",
  "manifest": "skills/dw-demo-ledger/assets/releases/10.29.8/manifest.json",
  "digest": "sha256:<snapshot digest>",
  "checkIds": ["pim.data-models.folder"]
}
```

`checkIds` holds check ids, not file paths: the `id` of a probe that a function in `functions/<area>.json` lists under `checks`, for a function the build requests. Take the ids from those lists. A probe file that no function references is not lockable, and the repository validator refuses such a file. The digest is SHA256 of sorted release-relative path and SHA256 lines for every file in the snapshot, including manifest, function files, probes and evidence. Paths use forward slashes; digest input uses UTF-8 and LF, with one line `path:sha256hex` per file. Both content changes and file additions change it. Exclude no authored snapshot files.

The runner verifies the explicit check set and rejects unknown/duplicate ids. When it stops before a report, the error names the cause: the check id and why it was refused, the manifest path the lock states beside the one selected, both digests, or the file and schema that disagree. Any other exception stays generic, so no credential or response body is printed. An edition locks that set, never all checks from a newer producer. Requested functions with no checks are UNVERIFIED. Unknown function ids are errors. The git commit additionally pins scripts and profiles; consumers must execute from that commit, not pair an old snapshot with a new runner.

Repository validation uses PowerShell 7 `Test-Json` for the same draft-7 schemas as the runner, and checks unique IDs, probe ownership/existence, capability-function references, coverage references, implemented handler/surface pairs, the assertion kind per handler, read-tool and read-query allowlists, the arguments a handler needs (`projection.rowsPath`, `featureTypeName`, a file scope, a settings key), SQL localOnly and SQL text, the manifest's schema and `dwVersion`, profile keys, and that every JSON file in a snapshot parses. Non-ID capability descriptions, app names and flag keys are external facts, not function IDs; they stay unknown until measured.

The optional profile path resolves beneath the skill's assets directory and contains `{schema:1, id, expectations:{checkId:{...assertion overrides...}}}`. The build carries defaultLanguage, pimShop, families, attributes, productScope and editLayout when those checks need them. No SQL connection or tokens belong in a build file. Connection parameters/environment are runtime input only.

Requires predicates have kind (flag/app/licence/capability), id, expected and optional probe. A runner must establish them from target facts; absence means UNVERIFIED, never an assumption of enabled. For `flag` and `capability` requirements `expected` is a boolean, compared without coercion: text such as `"false"` is refused by the schema and is ERROR in the runner. A requirement gates every check of its function, so put on a function only what all of its checks need; a precondition of one action belongs in the description or that check's planned reason. A false flag is DISABLED; a known incompatible component is UNSUPPORTED. No requires is inferred from a feature's name.

Rulings map function ids to `{applies:false, rule, evidence}`. A NOT-APPLICABLE ruling must name an allowed reason and carry evidence; where that reason has a probe, it must pass. `applies` is a boolean and `evidence` is non-blank text: the build schema refuses anything else, and the runner reports such a ruling as ERROR. A missing binding, licence or declaration is not a ruling. Runtime verification may be stricter than structural JSON validation.

Grounds are per function. Optional configuration functions that a reproduced catalogue may simply not use (coupons, vouchers, gift cards, loyalty, order and order line fields, payment fees, track and trace and similar) carry the ground `catalogue-does-not-use`; its evidence names the source pages or census items reviewed. Core functions never carry it. A function without a fitting ground is declared and measured, or left out of the build.

## Discovery and reports

Capabilities match assets/target-capabilities.schema.json. Read MCP tools/list including pagination, the Admin descriptor and a known safe authenticated query. A public descriptor never proves authentication. SQL is enabled only by an explicit local SqlServer parameter; hosted mode never attempts database discovery. File access is checked per path during execution. Observed versions may be unknown.

Reports match assets/report.schema.json and include the lock, compatibility, capabilities, checks, counts and errors. Every check names its surface/binding, proof level, result, reason, measured/expected observations and optional bounded offender list. No token, connection string or raw exception body is emitted. Failure to load a handler is ERROR; no eligible binding is UNVERIFIED. Empty requested check sets cannot pass.

PASS proves the specified assertion. FAIL disproves it with a valid observation. ERROR means execution or contract failure. UNVERIFIED means evidence is insufficient. UNSUPPORTED means known incompatible capability/version. DISABLED means a required feature is off. NOT-APPLICABLE means an evidenced allowed exclusion. Aggregate success requires only PASS/NOT-APPLICABLE and at least one evaluated requirement, which is at least one PASS: a run that holds NOT-APPLICABLE rulings alone is UNVERIFIED. All other states prevent readiness. Count states separately. ERROR takes precedence, then FAIL, UNSUPPORTED, DISABLED, UNVERIFIED, otherwise PASS.

An exact baseline mismatch blocks normal execution. An explicit diagnostic switch may observe another version, but compatibility.matches remains false and the aggregate cannot be PASS. Baseline claims require baseline measurements. SQL reads owe no cache flush because they do not mutate anything.

The runner reads the public version descriptor again after all checks. A changed
or unavailable final version sets compatibility.matches to false and records an
error note; the aggregate cannot be PASS. Individual observations remain available
for diagnosis, but cannot certify the starting release across a concurrent upgrade.
