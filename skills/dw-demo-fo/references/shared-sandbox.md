# Shared-sandbox discipline: many customer demos, one F&O tenant

One sandbox carrying several customer demos is the point of this skill: a legal entity is cheap, an
environment is not. The cost is that everything outside the `dataAreaId` boundary is shared, and a careless
demo build degrades every other demo in the tenant.

## Agree the namespace before creating anything

| Artefact | Convention |
|---|---|
| Legal entity code | 4 characters at most, recognisable per demo, agreed with the environment owner; never reuse a donor or standard demo-data code |
| Product numbers | `<CODE>-` prefix |
| Product attributes and attribute groups | `<CODE> ` prefix |
| Category hierarchies and categories | `<CODE> ` prefix |
| Sites, warehouses, item/customer groups | per company: no prefix needed, use the customer's own names |
| Number sequence codes | per company: the sequence *codes* are company-scoped; only shared codes need care |
| Users / app registrations | one integration app per tenant is enough; do not mint one per demo |

The rule of thumb: **anything the boundary table in [company-profile.md](company-profile.md) puts in the
tenant-wide column needs a prefix.** Anything in the per-company column carries the customer's own vocabulary
and needs none.

## Read-only against everything you did not create

- The **donor company** and the **golden company** are reference data. Copy *from* it; never edit it to make a copy easier.
- Neighbouring demo companies are someone else's live demo. Their data is not a fixture to borrow.
- Shared configuration (chart of accounts, fiscal calendars, units of measure, languages) is edited only by
  agreement: a renamed unit of measure breaks every company at once.
- Never rename a shared product attribute or category to fit this demo; create a prefixed one.

## Throttling is shared too

Service-protection limits key on the calling app, and one app usually serves every demo in the tenant. A bulk
import, a discovery census, and a live demo pull compete for the same budget. Pace jobs, honour `Retry-After`
on HTTP 429, and do not run a bulk seed while someone else is presenting. If demos are frequent enough for
this to bite, that is the argument for a second app registration with its own throttling priority, not for
running the seed faster.

## Announce and record

Keep a one-line entry per demo company somewhere the environment owner can see it: company code, what it is
for, who built it, and whether it is still needed. A sandbox with unexplained companies gets cleaned by
whoever owns it, on their schedule.

Per demo, the engagement folder holds the profile, the seed scripts and the run log; the golden package is kept
beside the golden company's run log ([demo-company.md](demo-company.md) §6). Nothing customer-identifying goes into the skill or the plugin.

## The environment is not durable

An environment refresh, a copy from production, a point-in-time restore, or a deallocation removes demo
companies with no warning to their owners. Plan for it:

- the seed must be re-runnable end to end;
- the golden configuration package lives outside the environment;
- the demo's DW side must tolerate an empty F&O for a few minutes without looking broken (cached catalog,
  last-sync state); check this before a customer-facing run;
- before any demo, run the read-only verification ([demo-company.md](demo-company.md) §5). It is cheap and it
  is the only thing that distinguishes "the company is gone" from "the job is misconfigured" while an audience
  waits.

## Retiring a demo company

Retire, do not delete. Mark the company **dormant** in the shared list and unbind its DW site (disable or
remove the jobs that carry its `dataAreaId`); the legal entity stays. A legal entity with transactions cannot
be deleted, and clearing them gains nothing. A dormant company can be handed to the next demo by re-running
the package import and the seed over it ([demo-company.md](demo-company.md) §6).
