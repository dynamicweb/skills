# What is verified, and what is not

The evidence behind this skill's claims, grouped by how firmly each one is established. Read this before relying on anything surprising. Reached from [SKILL.md](../SKILL.md).

Claims here do not all carry the same weight. Treat the last group with suspicion and check before
relying on it.

**Verified live against a 10.29 cloud solution:** API-key auth through
`--host`/`--apiKey`; `dw files` list, import and export; the missing-`-o` silent skip and the `model: []`
tell; automatic creation of missing remote directories; a `.cshtml` deploy taking effect with no recycle;
`FileDelete` with a bare body; reading `/Files/Templates` through MCP; MCP `set_paragraph_item_fields`
leaving sibling fields intact.

**Read from the CLI source but never executed:** the `dw command -l` dead-code bug. (An earlier draft
also listed the version-specific table here, on the grounds that only 1.0.16 was installed. That was
already contradicted by the paragraph below, which records the same behaviour being tested on 1.1.2.)

**Reported by the solution owner, not tested:** the `recycle.txt` mechanism in `System/CloudHosting`.
The `-o` consequence described there is inferred from verified upload behaviour, not observed on the
recycle path. Likewise the `-q` semantics — that a non-queued install hot-loads the assembly into the
running application and that neither variant restarts it. An earlier draft of this skill wrongly claimed
a non-queued install recycles the solution; do not reintroduce that.

**Tested on both 1.0.16 and 1.1.2:** the add-in install loop — a purpose-built class library was
compiled and installed queued (`-q`) against a live solution on each version. Confirmed: upload target
`System/AddIns/Local`, the `model` path, `Addin installed`, exit 0 on success and 1 on a bad path, the
1.0.16 wildcard crash, and on 1.1.2 both working wildcards (with `meta.resolvedPath`) and the
`--output json` envelope on success and failure.

**Tested and found NOT to work as expected:** a non-queued install did not make the add-in's type
available, and neither did a subsequent full recycle. `dw install` reporting success is therefore not
evidence the add-in works — that conclusion stands.

The root cause was later found, and it was not the install path. Two distinct failures were being read as
one. An add-in compiled against **newer** package versions than the host runs fails to load, silently,
with only a `ReflectionTypeLoadException` in
`/Files/System/Log/AddInManager/TypeLoadErrors.log` to show for it — A/B verified against a 10.29.1 host.
Separately, an UpdateProvider that appeared never to run had in fact run and thrown: `SqlUpdate.AddTable`
requires the caller to supply the parentheses around the column list, and the resulting `SqlException` was
sitting in the `GeneralLog` table from the first attempt. Three theories were built before that log was
read. Read the log first.

**Verified live:** the `recycle.txt` marker genuinely recycles the solution (503 during, 200 after), the
platform deletes the marker afterwards, and `dw files` crashes on the HTML error page served mid-recycle.

**Since verified:** an add-in built against package versions matching the host does load and run. A
class library referencing `Dynamicweb.Application.UI` `10.*` was installed on the same 10.29.1 solution
and its screens rendered in the admin.

**Verified on 1.1.3 from outside the CLI's own checkout:** `dw --version` reports the CLI's
version from a directory with no `package.json`, from one holding an unrelated `package.json`, and from
`C:\Windows\System32`; `dw swift` clones the Swift release; and a failing `dw query` no longer puts the
API key in its output. Measuring `dw --version` from inside the CLI checkout is worthless — the old
guess found that checkout's own `package.json` and looked correct.
