# Release evidence and snapshots

For Truvio Commerce (powered by Dynamicweb), a new release creates a new candidate snapshot. Never change the meaning of a consumer's locked check set.

1. Capture the shipped package identities, release notes, documentation inventory and component-source mappings for both releases. A source enum or current documentation page does not prove a feature shipped in an older baseline.
2. Produce a general candidate list from that evidence, recording id, change, source and reason. Separate platform additions from corrections to an incomplete inventory. Record removed ids and their replacements, not silent disappearance.
3. Run [Find-DwReleaseFunctions.ps1](../scripts/Find-DwReleaseFunctions.ps1) to collect the target milestone's work items, public package type/enum differences, added FeatureBase subclasses and a read-only local database schema comparison. Save its raw output before review. It refuses to overwrite that file. Then run [Compare-DwLedgerRelease.ps1](../scripts/Compare-DwLedgerRelease.ps1) with the two manifests and reviewed candidate file. Both outputs require review.
4. Review the candidate and implement or update an observation binding. Keep unsupported flags, app versions and missing read surfaces explicit. A planned binding cannot produce PASS.
5. Test positive and red controls, including missing data, missing handler and incomplete pagination. Compare equivalent MCP and local SQL observations when both are available; a valid disagreement remains evidence of a problem.
6. Measure on the exact baseline and compatible components. Mark the entries measured only with retained evidence. A diagnostic newer-host run never establishes older-release support.
7. Publish the immutable commit and snapshot digest. New editions may select it; existing editions retain their previous lock until deliberately upgraded ("Re-locking an existing build" below).

Run the comparison as a local report operation:

```powershell
pwsh -NoProfile -File scripts/Compare-DwLedgerRelease.ps1 -Before $oldManifest -After $newManifest -EvidenceFile $candidateFile -OutFile $deltaFile
```

Run the generic scanner without a feature search term:

```powershell
pwsh -NoProfile -File scripts/Find-DwReleaseFunctions.ps1 -BeforeVersion $a -AfterVersion $b -EvidenceDirectory $cache -OutFile $raw -SqlServer $server -BeforeDatabase $dbA -AfterDatabase $dbB -BeforeBaseUrl $urlA -AfterBaseUrl $urlB
```

The scan can be rerun from retained evidence. `-ChangelogFile` takes the retained
`changelog-response.json`, and no changelog request is made; `-ChangelogDigest` refuses a capture
whose digest is not the recorded one. Evidence in the directory is written once: the same content
again is left alone, and a changelog capture, ring listing or schema capture that differs from the
retained file stops the scan instead of replacing it. Output members are ordered, so two scans of
the same evidence differ in `generatedAt` only and have the same `candidatesDigest`. A work item
listed under several releases is one candidate that names them all.

Capture the earlier schema before upgrading its host, and capture the later schema from the same
database after the upgrade. Each schema capture records its database name, a `sourceId` (a digest
of server and database, no machine name) and the capture time. The scan reports
`schemaComparison`: only `same-database` makes a column difference a release difference; with
`different-databases` or `unknown-provenance` it warns that site differences are in the list, and
every added or missing column needs a second source before it is admitted or rejected. BeforeSchemaFile and AfterSchemaFile
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

An inventory correction is a capability a build found that the inventory missed. It is not a
platform addition: record it in the snapshot's `delta.json` `corrections` (and a `mapped` entry
when a proposal is an existing function), review it in `delta-review.json` `corrections`, raise
the manifest `revision`, and name the source issue. Check fixes go in `checkCorrections`; a
correction makes the check measure what its `proves` says and never weakens an assertion to let
a build pass. Admit the same entry to an earlier snapshot only from that release's package bytes
and schema (its `evidence/admission.json` `corrections`); otherwise list it as not admitted.
Each implemented SQL read gets a green and a red fixture control
([Corrections.Tests.ps1](../scripts/tests/Corrections.Tests.ps1)).

The release experiment starts with a genuine pre-feature release and discovers capabilities
through general evidence. Feature-specific implementation research happens after the raw
scan is saved; it must not change what that scan originally found.

## Re-locking an existing build

A snapshot revision edits the release directory in place, so its digest changes and a build
locked on the earlier revision stops with a digest mismatch on any later commit. That build
keeps running from its own lock commit. Moving it to the current revision is a deliberate
upgrade, and the earlier report does not carry over:

1. Check out the commit to lock, clean. On a commit older than the repository's
   `.gitattributes`, check out with `core.autocrlf=false`: the digest is over bytes.
2. Run the re-lock report. Without `-OutFile` it writes nothing:

```powershell
pwsh -NoProfile -File scripts/Update-DwLedgerLock.ps1 -BuildFile $build -Manifest $manifest -OutFile $newBuild
```

3. Read the report. `removedChecks` are dropped from the lock; the snapshot's `delta.json` says
   what replaced them. `removedFunctions` and `invalidRulings` (with `groundsNow`, the grounds the
   function has in this revision) are decisions: edit `functions` and `rulings` in the build
   file, then run it again. While one is open the exit code is 1 and no file is written.
   `newChecks` lists the checks of the requested functions that the old lock does not hold;
   `-IncludeNewChecks` locks them, otherwise they stay out and are not proven.
4. Run the checks with the new build file. A re-locked build is a new claim: a ground that was
   replaced may no longer apply, and checks that replaced a removed one may fail on an unchanged
   site.

The script never rewrites `functions` or `rulings`, never overwrites a build file and refuses a
checkout with uncommitted changes.
