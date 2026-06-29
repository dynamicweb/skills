# Foundational candidate → dw-source-explorer

> **FOUNDATIONAL CANDIDATE.** Vendor-generic DW10 assembly-introspection technique, staged here for
> a future fold-up into `dw-source-explorer`. No demo/customer content. When folded, move this body
> into `dw-source-explorer` and re-target the pointers in the demo skills. Until then, the demo
> skills reference this file. Do not add demo specifics here.

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
