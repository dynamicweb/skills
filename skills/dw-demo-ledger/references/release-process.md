# Release evidence and snapshots

For Truvio Commerce (powered by Dynamicweb), a new release creates a new candidate snapshot. Never change the meaning of a consumer's locked check set.

1. Capture the shipped package identities, release notes, documentation inventory and component-source mappings for both releases. A source enum or current documentation page does not prove a feature shipped in an older baseline.
2. Produce a general candidate list from that evidence, recording id, change, source and reason. Separate platform additions from corrections to an incomplete inventory. Record removed ids and their replacements, not silent disappearance.
3. Run [Find-DwReleaseFunctions.ps1](../scripts/Find-DwReleaseFunctions.ps1) to collect the target milestone's work items, public package type/enum differences, added FeatureBase subclasses and a read-only local database schema comparison. Save its raw output before review. It refuses to overwrite that file. Then run [Compare-DwLedgerRelease.ps1](../scripts/Compare-DwLedgerRelease.ps1) with the two manifests and reviewed candidate file. Both outputs require review.
4. Review the candidate and implement or update an observation binding. Keep unsupported flags, app versions and missing read surfaces explicit. A planned binding cannot produce PASS.
5. Test positive and red controls, including missing data, missing handler and incomplete pagination. Compare equivalent MCP and local SQL observations when both are available; a valid disagreement remains evidence of a problem.
6. Measure on the exact baseline and compatible components. Mark the entries measured only with retained evidence. A diagnostic newer-host run never establishes older-release support.
7. Publish the immutable commit and snapshot digest. New editions may select it; existing editions retain their previous lock until deliberately upgraded.

Run the comparison as a local report operation:

```powershell
pwsh -NoProfile -File scripts/Compare-DwLedgerRelease.ps1 -Before $oldManifest -After $newManifest -EvidenceFile $candidateFile -OutFile $deltaFile
```

Run the generic scanner without a feature search term:

```powershell
pwsh -NoProfile -File scripts/Find-DwReleaseFunctions.ps1 -BeforeVersion $a -AfterVersion $b -EvidenceDirectory $cache -OutFile $raw -SqlServer $server -BeforeDatabase $dbA -AfterDatabase $dbB -BeforeBaseUrl $urlA -AfterBaseUrl $urlB
```

Capture the earlier schema before upgrading its host. BeforeSchemaFile and AfterSchemaFile
accept retained captures; the recorded version must match the requested side. Compare
INFORMATION_SCHEMA columns and primary keys, preserving site-specific differences as
candidates rather than assuming every schema difference is a release addition. Package
bytes and selected assembly digests remain in the evidence cache. PEReader reads metadata
tables; no target assembly is loaded or executed. The changelog collector resolves moving
ring numbers by milestone and excludes later patches. An unavailable milestone or package
fails collection instead of producing an empty apparent success.

The earlier snapshot is a candidate test inventory, not a claim that current documentation
applies to old versions. Its admission record must name exclusions supported by old package
and schema evidence. Keep unverifiable candidates visibly unverified. A newly found function
gets a reviewed entry and executable proof, or a planned binding that cannot pass.

The release experiment starts with a genuine pre-feature release and discovers capabilities
through general evidence. Feature-specific implementation research happens after the raw
scan is saved; it must not change what that scan originally found.
