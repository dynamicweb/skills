# Release evidence and snapshots

For Truvio Commerce (powered by Dynamicweb), a new release creates a new candidate snapshot. Never change the meaning of a consumer's locked check set.

1. Capture the shipped package identities, release notes, documentation inventory and component-source mappings for both releases. A source enum or current documentation page does not prove a feature shipped in an older baseline.
2. Produce a general candidate list from that evidence, recording id, change, source and reason. Separate platform additions from corrections to an incomplete inventory. Record removed ids and their replacements, not silent disappearance.
3. Run [Compare-DwLedgerRelease.ps1](../scripts/Compare-DwLedgerRelease.ps1) with the two manifests and candidate file. It compares snapshots and ingests supplied evidence; it is deliberately not an autonomous release-note crawler. Its output is proposed, not approved.
4. Review the candidate and implement or update an observation binding. Keep unsupported flags, app versions and missing read surfaces explicit. A planned binding cannot produce PASS.
5. Test positive and red controls, including missing data, missing handler and incomplete pagination. Compare equivalent MCP and local SQL observations when both are available; a valid disagreement remains evidence of a problem.
6. Measure on the exact baseline and compatible components. Mark the entries measured only with retained evidence. A diagnostic newer-host run never establishes older-release support.
7. Publish the immutable commit and snapshot digest. New editions may select it; existing editions retain their previous lock until deliberately upgraded.

Run the comparison as a local report operation:

```powershell
pwsh -NoProfile -File scripts/Compare-DwLedgerRelease.ps1 -Before $oldManifest -After $newManifest -EvidenceFile $candidateFile -OutFile $deltaFile
```

The Matrix experiment must start with a genuine pre-feature release and discover the capability through general release evidence. Do not seed a feature-specific scanner or infer its first release from its appearance in a current API. The initial snapshot deliberately omits Matrix until this is proved.
