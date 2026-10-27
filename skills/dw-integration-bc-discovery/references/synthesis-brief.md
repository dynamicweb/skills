# Synthesis and owner review

Fill [the data-model brief](../assets/templates/data-model-brief.template.md), retaining
evidence paths and unknowns. Present the populated model first, then the proposed Integration
Framework activities. The review should be able to trace a cart line through item/UOM/price,
customer/ship-to, fulfilment, BC order, invoice and payment state.

The implementation handoff contains a non-secret connection manifest, actual source schemas,
company/key map, ownership allowlists, activity dependency order, acceptance scenarios,
operations/recovery policy and the unresolved decision list. Credentials remain vault references.

Use the states **observed**, **documented**, **proposed**, and **pending owner decision** for
each important assertion. The skill's generic recipe is not evidence that the selected tenant
or extension has passed an acceptance test.

Done: the ERP owner has reviewed the key spine and ownership split, and every build blocker
has an owner or a recorded decision. Route the build to
[`dw-integration-bc`](../../dw-integration-bc/SKILL.md).
