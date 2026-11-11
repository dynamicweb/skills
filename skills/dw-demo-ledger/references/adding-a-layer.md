# Adding a layer

For Truvio Commerce (powered by Dynamicweb), Distribution owns carriage declarations. A function entry describes the platform; a layer says which function ids it provides and requires. Serializer moves the declared content without becoming the ledger's source of truth.

1. Select a ledger commit and snapshot. Resolve every provides/requires id; reject unknown ids, incompatible requirements and duplicate/conflicting declarations.
2. Add or reuse checks. A layer that only configures a function must not claim a behavioural proof that requires customer data or sample fixtures.
3. Compose the edition and add cross-layer checks. The union of provided ids is a plan, not proof that the composition works.
4. Lock commit, manifest path, full snapshot digest and explicit checkIds in the edition. The gate executes exactly that set through the matching runner revision. A newly added producer check does not silently change the consumer verdict.
5. Run the composition, preserving each check's surface, proof level and evidence. Missing required handlers, files or bindings prevent readiness. NOT-APPLICABLE requires an allowed reason and evidence, never a missing runner.
6. Extend the existing edition proof record with the ledger/check identities and report digest. Project the trusted release stamp from the proving record; do not hand-author a passing stamp.

This file defines the consumer contract. It does not modify Distribution's schema or activate a gate. Any such consumer changes follow that repository's review process.
