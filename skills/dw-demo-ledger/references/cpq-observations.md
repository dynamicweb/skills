# CPQ observations and parity

Truvio Commerce (powered by Dynamicweb) CPQ observations inspect stored facts without running
the configurator or changing a target. The snapshot remains candidate. [dw 10.29.8]

## Implemented scope

Revision 5 registers five local SQL bindings: `installation.schema`, `model-versions.integrity`,
`inputs.declaration`, `conditions.dialect` and `input-rules.loader`. Each has positive and red
controls in [Cpq.Tests.ps1](../scripts/tests/Cpq.Tests.ps1). No MCP or Admin binding is promoted.
Discovery still prefers those surfaces; an advertised tool is not proof of authorized access
or of a complete projection. Studio's request-context restriction remains in force.

[Cpq.Read.ps1](../scripts/Cpq.Read.ps1) uses typed IDs, integrated authentication, fixed SELECTs
and one serializable read transaction. Supply a local server and database explicitly. It reads
one declared model/version and its child rows, schema, catalogue identifiers and page bindings.
It never reads saved cards, quotes, orders or users. It does not execute stored lookup SQL.

Declare `build.expected.cpq.modelId` and `versionId` before reading. For `inputs.declaration`,
also supply `inputs`, an independent array containing each input's `InputName`, `InputGroupId`,
`InputType`, `InputRequired`, `InputVisible`, `InputReadOnly`, `InputEnabled`, `InputSeq`,
`InputDefaultValue`, `InputOptions` and `InputSettings`. Options/settings are parsed JSON;
array order and value types matter. Defaults stay literal. Missing or additional inputs fail.

For `model-versions.integrity`, declare `children`, keyed by each child table, with its exact
expected integer IDs, including empty arrays. Tables are CPQGroup, CPQInput, CPQInputRule,
CPQBOMRule, CPQPriceRule, CPQRouteRule, CPQModelVariable, CPQOutputRule and CPQOutputAction.
The observer checks ownership, declared membership, symbolic names, parent cycles and references
in conditions, actions, quantities, price/output fields, group gates and lookup parameters.
Declarations must come from the spec/identity map, never from the read being judged.

[Cpq.Json.ps1](../scripts/Cpq.Json.ps1) refuses duplicate JSON keys, unsafe object tests,
unknown operators, malformed references and incorrectly cased group operators. It accepts the
reviewed three-element tuples and explicit AND/OR groups, including nested lists. An empty
condition document is unconditional; an empty group is refused. This checks syntax and reference
resolution, not truth-table semantics. Variable values and input defaults are not evaluated.

[Cpq.Observations.ps1](../scripts/Cpq.Observations.ps1) returns incomplete observations when
independent expectations or required projections are missing. The schema inventory in
[cpq-columns.json](../assets/cpq-columns.json) covers 119 required columns across twelve tables;
it records SQL types, not an exhaustive schema compatibility certificate.

## Measured parity and limits

A local read of a model/version on a host with the pinned CPQ_Admin package inspected 119 required
schema columns, 15 condition-bearing rows and three enabled input rules. These three intents
passed their stored-data assertions. In-memory red controls changed a schema type, inserted an
unsupported operator and removed CPQOptions; each failed, with no target mutation.

For input declarations and child membership the read had 44 inputs, nine groups, four input
rules, one BOM rule and one price rule. There was no independent expected model declaration,
so those intents remained UNVERIFIED. Unit fixtures prove exact comparison, missing/extra
subjects, mismatched flags, wrong parents, duplicate names and unresolved references.

This is parity between the fixed SQL projection and the normalized handler, not parity with
an MCP/Admin read. MCP discovery returned the Studio read/analyze names but their source policy
restricts the request context; no external authorization was assumed. The public Admin descriptor
was readable, while an unauthenticated model query returned 401. No Admin credential was supplied.

The measured host ran a DW 10.30.2 prerelease and Studio 0.6.2. Its installed runtime DLL differed
from the original pinned DW_CPQ_API package entry. These facts cannot prove the baseline or the
planned Studio 0.7.0 combination. The ordinary runner establishes an `app` requirement from the installed add-in folder
(`<id>.<version>`), which is the installed package and its version, never from SQL rows or the
build declaration. That opens the gate for the stored-data checks; it is not loaded-assembly
evidence. A claim about the loaded runtime still needs loaded hash/version evidence, and its
bindings stay planned until a producer supplies it.

## Readers that remain planned

Normalized comparators exist for loaded assemblies, complete page/navigation/tab/theme scope,
pricing context and ERP configuration. Their live adapters remain planned: the SQL snapshot
cannot establish loaded hashes, resolved theme/tab assets or effective customer price context.
Loaded inventories must include all identities and hashes from an independently resolved lock;
installed files alone are insufficient. No arbitrary caller projection is a trusted producer.

BOM and lookup readers report reference findings but remain incomplete. They cannot prove
dynamic quantity semantics, all option BOMs, rule non-overlap or safe parameterized lookup
execution. No green partial result is promoted into their broader acceptance intent.

[Cpq.Receipts.ps1](../scripts/Cpq.Receipts.ps1) reads every behavioural receipt using the
Distribution v1 validator. Load `tools/ci/Cpq.Contracts.ps1` and `Cpq.Receipts.ps1` from the
consumer's independently pinned and reviewed Distribution checkout first. The reader never
loads code or schemas from paths embedded in a receipt. Supply the independent trusted context,
digest, delivery time, clock, spec, package lock and behavior declaration to `Trust`.

Validated envelopes retain failure results. BOM and sell-price payloads are compared with the
independent spec cases; an altered business value fails despite a producer's PASS label. Even
matching initial cases remain UNVERIFIED: they do not cover the full selection, cost, persistence
and handoff intent. Other behavioural payloads remain readable but unverified until a registered
producer and domain assertions exist. All 21 behavioural bindings stay planned.

Run `Invoke-Pester -Path skills/dw-demo-ledger/scripts/tests -CI` in the checkout. Receipt-reader
integration tests in Distribution accept an explicit skills checkout path; neither repository
embeds a machine path or silently discovers another working tree.
