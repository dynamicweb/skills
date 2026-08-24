# Assembly introspection — reflection discipline and MetadataReader

## Reflection answers "does it exist", never "why is it not selected"

**When a documented admin-UI affordance is measurably dead, grep the reference material for the
affordance AND for the artefact it depends on BEFORE reflecting over the assemblies.** Reflection
starts only when that grep comes back empty, and the grep gets recorded next to the reflection so a
later reader can see it happened.

The reason is structural, not procedural. A reflection pass reads code and can only answer *does the
capability exist*. It cannot answer *why is this instance of it not selected*, because the selection
frequently depends on **data** — and data the pass never looked at. The shape that keeps producing
confident false negatives: a provider chooses whether to attach an action by testing a **filesystem
path** (`…FileName.StartsWith(MapPath("<a specific folder>"))`), so a capability that plainly exists in
the DLL is simply never invoked for artefacts stored somewhere else. Reflection then reports "the
feature does not exist on this version", the finding is recorded as a platform limitation, and a whole
workstream ships a workaround for something that was never broken.

Two habits close it:

- **Grep first, reflect second.** `grep -rn "<affordance>|<provider class>|<path constant>"` over the
  reference material. A hit usually carries the fix.
- **Before writing "platform gap", name the input the conclusion rests on** and check whether it is code
  or data. If it is data, the reflection pass could not have seen it.

## Discovering an installed AddIn's query/command surface with `MetadataReader`

When a DW10 AppStore AddIn exposes a `/admin/api/*` call surface that isn't documented anywhere
user-visible, you can re-derive the full inventory by reading the **metadata** of the installed
assembly. The Management API dispatcher routes by class name (endpoint = class name minus the
`Query`/`Command` suffix), so listing the `*Query` / `*Command` types in the DLL gives you the exact
endpoint list. PowerShell-only, no decompiler needed:

```powershell
Add-Type -AssemblyName System.Reflection.Metadata -ErrorAction SilentlyContinue
$dll = "<host>\wwwroot\Files\System\AddIns\Installed\<Package>.<ver>\lib\net10.0\<Package>.dll"
$stream = [System.IO.File]::OpenRead($dll)
try {
  $peReader = [System.Reflection.PortableExecutable.PEReader]::new($stream)
  $mr = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)
  $names = foreach ($h in $mr.TypeDefinitions) {
    $td = $mr.GetTypeDefinition($h)
    $ns = $mr.GetString($td.Namespace); $n = $mr.GetString($td.Name)
    if ($ns) { "$ns.$n" } else { $n }
  }
  "-- QUERIES --";  $names | Where-Object { $_ -match '\.Queries\.[A-Z][A-Za-z]+Query$' } | Sort-Object
  "-- COMMANDS --"; $names | Where-Object { $_ -match '\.Commands\.[A-Z][A-Za-z]+Command$' } | Sort-Object
} finally { $peReader.Dispose(); $stream.Dispose() }
```

### Why `MetadataReader`, not `Assembly.LoadFrom`

The `Query<>` / `Command<>` base types live in DW assemblies that don't load in PowerShell's default
context, so `Assembly.LoadFrom` raises `ReflectionTypeLoadException` and silently drops exactly the
query/command types you're after. `MetadataReader` reads type names directly from the PE file
**without resolving dependencies**, so it never hits the missing-base-type problem.

### Gotcha: `GetMetadataReader` is an extension method

`PEReaderExtensions.GetMetadataReader` is an extension method — PowerShell doesn't auto-discover it,
so call it as a static:
`[System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)`.

This technique generalises to any installed AddIn: swap the `<Package>` path and adjust the namespace
filter (`\.Queries\.` / `\.Commands\.`) to the package's own namespace layout.
