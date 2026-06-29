# cache-invalidation.md

> Post-mutation cache invalidation for a Dynamicweb 10 PIM build. Loaded from the dw-demo-pim SKILL.md "Where to find things" table.

The vendor-generic platform knowledge — the full post-mutation cache table, the edit-vs-insert
rule for content tables, the index-build-reads-through-cache ordering trap, and the
"when a mutation doesn't show up" resolution order — lives in the foundational candidate:

**→ [`../../dw-demo-base/references/foundational/cache-invalidation.md`](../../dw-demo-base/references/foundational/cache-invalidation.md)**

## Demo note — when to reach for the SQL fallback (and pay the cache cost)

The candidate's table is the rulebook for the **Direct SQL fallback** surface. In a demo build you
only land on it when MCP / Management API / admin-UI can't do the mutation — the decision to drop to
SQL-direct over MCP is governed by [`../../dw-demo-base/SKILL.md` "Surface priority for CREATES"](../../dw-demo-base/SKILL.md).
When you DO seed via SQL, the candidate's "Restart required?" column tells you what the seed owes you
afterward; budget the 30-second host bounce (or, on a hosted install, the bulk cache flush) into the
build step. If you used MCP, you are already done — don't "double-fix" by also restarting.
