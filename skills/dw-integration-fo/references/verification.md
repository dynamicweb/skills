# Verification ladder

## Contents

- [The rungs](#the-rungs)
- [Invariants for the rest of the solution](#invariants-for-the-rest-of-the-solution)
- [Proving stage 2 before F&O answers](#proving-stage-2-before-fo-answers)
- [Reading a run](#reading-a-run)
- [What to record](#what-to-record)

## The rungs

Climb in order; a rung that fails names the fix, and nothing above it is worth running.

| # | Rung | Pass | Fail means |
|---|---|---|---|
| 1 | Token | a client-credentials token for `https://<env>.operations.dynamics.com/.default` | tenant, client id or secret wrong (`AADSTS` code tells which) |
| 2 | Entity read, outside the platform | `CustomersV3?cross-company=true&$filter=dataAreaId eq '<CODE>'&$top=1` returns a row | 403: app not mapped to an F&O user; empty: wrong company code |
| 3 | Endpoint test | MCP `test_integration_endpoint` on the connection endpoint (`LegalEntities`) succeeds and lists `<CODE>` | the endpoint's authentication (re-save it from the vault) |
| 4 | Stage 1 row counts | each staging table's count equals `$count` of the same filtered entity set | a filter or `cross-company` mismatch between the endpoint and the count |
| 5 | Stage 2 row counts | each view's count equals the rows the integration owns in its target table | a key or an option (update-only, insert-only) blocking rows |
| 6 | Spot check | one item number, one customer account, one price, one on-hand figure read end to end: F&O -> staging -> view -> platform row -> storefront (as the persona the price is for) | the view's join or the price scope |
| 7 | Re-run | a second run of the whole chain changes zero rows (compare counts and a checksum of the owned rows) | a key that does not match its own previous output |
| 8 | Negative test | delete one owned row or blank one value, re-run, confirm it returns; restore from backup | a job that "succeeds" without writing |

`$count` answers begin with a byte-order mark; strip `U+FEFF` before comparing numbers.

## Invariants for the rest of the solution

Before the first stage-2 run, record counts of everything the integration must not touch, and assert them after
every run: products and prices that are not the integration's, orders, users, groups. With prefixed ids this is
one query:

```sql
-- SQL. Local installs only: a read-only assertion, no cache flush owed.
SELECT (SELECT COUNT(*) FROM EcomProducts WHERE ProductId NOT LIKE '<P>%')  AS other_products,
       (SELECT COUNT(*) FROM EcomPrices   WHERE PriceId   NOT LIKE '<P>P%') AS other_prices,
       (SELECT COUNT(*) FROM EcomOrders   WHERE OrderId   NOT LIKE '<P>I%') AS other_orders;
```

A copy-only backup before the first run makes every later mistake a restore, not a reconstruction.

## Proving stage 2 before F&O answers

Stage 2 reads only staging tables, so it can be proven while the endpoints still cannot authenticate:

1. Insert a handful of rows into each staging table, in F&O's own shape (property names, enum symbols, the
   `1900-01-01` open date, the company code), each id clearly marked as test data.
2. Run the stage-2 activities; check rungs 5 and 7 against those rows, and the invariants.
3. Remove the test rows from staging **and** the rows they produced in the platform tables (prefixed ids make
   this a `LIKE`), then assert the invariants again.

The first real stage-1 run mirrors each staging table, so any test row left behind in staging disappears there;
rows it produced in platform tables do not, which is why step 3 removes both.

## Reading a run

- `run_integration_activity` queues. Poll `get_integration_activity_status` until neither running nor queued.
- `get_integration_activity_logs` returns the parsed log; the platform keeps the file under
  `Files/System/Log/DataIntegration/<group>/<activity><stamp>.log`, which is the fallback when the name holds a
  character the log lookup cannot handle.
- A stage-1 log shows the readiness probe first (`Checking if endpoint ... is ready for use on URL ...?$top=1`),
  then one line per page. A string of `Attempt n of 10 failed` lines is an authentication or reachability problem,
  not a data problem.
- `Job succeeded` means rows were processed. The counts are the evidence.

## What to record

Per run, in the engagement folder: the activity, start and end, status, rows landed or applied, the invariants
before and after, and the backup the run could be restored from. A run order table plus these counts is the README a
second person needs to repeat the integration.
