# sql-direct-seeding.md — the retired SQL motion, and what replaces it

## Contents

- [The rule that replaces it — the Admin UI is API-first](#the-rule-that-replaces-it--the-admin-ui-is-api-first)
- [Why an API write and a SQL write are not equivalent — visibility](#why-an-api-write-and-a-sql-write-are-not-equivalent--visibility)
- [Rebuilding the product index after a membership change](#rebuilding-the-product-index-after-a-membership-change)
- [Scheduled-task creation semantics (`TaskSaveCommand`)](#scheduled-task-creation-semantics-tasksavecommand)
- [If you are diagnosing rows that were already SQL-seeded](#if-you-are-diagnosing-rows-that-were-already-sql-seeded)
- [Cross-references](#cross-references)

> **This recipe is retired.** "Seed / edit content by writing rows directly to the DB (SQL-direct, or
> SQL through a scheduled task) because MCP/the API is out of reach" is no longer a sanctioned demo
> motion. It taught escaping to SQL whenever the API got hard; that reflex hides real
> `/Admin/Api` endpoints and produces half-wired rows the domain services never bless.

## The rule that replaces it — the Admin UI is API-first

Every admin action lands on `/Admin/Api`. The admin UI is a SPA client of that API — **if the UI can do
it, an `/Admin/Api` call exists.** So the path for any content create/edit is:

1. **MCP** (`save_pages` / `save_grid_rows` / `save_paragraphs` / `set_item_field_values` / …) — first choice;
   it runs DW's domain services (cache invalidation, `ItemList`/`ItemListRelation` wiring, sibling links,
   validation) that raw SQL skips.
2. **Management API** — when MCP doesn't expose the operation. Discover the endpoint from `/admin/api/docs/`,
   the `dw10source` command classes, or by driving the admin UI **read-only** under Playwright and reading
   the SPA's own traffic (`mcp__playwright__browser_network_requests`), then replay that call headlessly. This
   is exactly how the repeater-child (`Swift-v2_Slider` slide) edit path was recovered —
   `POST /Admin/Api/ParagraphSave`, no SQL, no recycle — see
   [`../../dw-demo-base/references/foundational/content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md)
   §2 "How repeater children are stored — and the Management API edit path".
3. **Do NOT reach for SQL — direct or via `RunSqlScheduledTaskAddIn` — when the API gets hard.** If the API
   genuinely seems to lack a surface, **file a learning** so the gap is captured and closed, rather than
   escaping to SQL and shipping unblessed rows.

The full surface contract (which surface exists on which instance type, and the narrow, still-sanctioned
SQL cases — cleanup/teardown and reads on a **local** install only) is owned by
[`../../dw-demo-base/references/surface-priority.md`](../../dw-demo-base/references/surface-priority.md).

## Why an API write and a SQL write are not equivalent — visibility

The reason the rule above is a rule and not a preference: **an API command that owns the entity invalidates
that entity's in-process cache as part of the write; a SQL row does not, and no API call reliably
retro-warms a cache the SQL write went behind.** On a host with no self-service recycle, that difference is
the difference between "seeded" and "staged until someone restarts the app".

- **Group → product membership.** `POST /Admin/Api/ProductGroupRelationSave {GroupIds:[…], Ids:[…]}` (call it
  for **both** the top group and the subgroup) invalidates the relation cache in-process: `GetCatalogGroupProducts`
  and a following index build see the new membership immediately, with **no recycle**. A raw `INSERT` into
  `EcomGroupProductRelation` writes correct rows that stay invisible to the catalog and to the index builder
  until the process recycles.
- **Product → product relations.** Same class, worse. Raw `INSERT`s into `EcomProductsRelated` never reach the
  related-products slider, and `ProductRelatedSave` **cannot** warm the cache afterwards — it resolves through
  the same stale collection and returns `404 "The related product entry is not found"` for the pairs you just
  inserted. `CacheInformationRefresh` across every Ecommerce service and repeated Full index rebuilds do not
  reach it either. Once relations exist only as SQL rows, that data is **restart-gated**: record it as staged in
  the run notes, not as shipped.
- **Details groups fail silently.** An `EcomDetailsGroup` created by a raw `INSERT` that names neither
  `DetailsGroupControlType` nor `DetailsGroupInheritanceType` leaves both `NULL`, and the renderer **skips a
  NULL-control-type group without logging** — a PDP downloads/media section renders nothing while the
  `EcomDetails` rows are correct and every file serves `200`. Every group the renderer actually emits carries
  `DetailsGroupControlType = 0` (stock file groups: control `0`, inheritance `3`). Setting both on the group
  makes the section render with no recycle. Any raw-SQL details-group insert must name both columns.
- **`ItemType_*` values written by SQL are OVERWRITTEN by the paragraph cache on the next `ParagraphSave`.**
  The worst shape in this family, because it reverts *later*, under someone else's edit. Item field values
  are cached, that cache **survives `CacheInformationRefresh`**, and the next `ParagraphSave` on the owning
  paragraph writes the cached pre-SQL values back over your rows. So the sequence reads as three separate
  bugs: the SQL write is invisible live, a flush does not surface it, and then it silently disappears.
  ```
  UPDATE ItemType_<Prefix>_<Concept> SET <field> = …   -> row correct in SQL, absent from the rendered page
  POST /Admin/Api/CacheInformationRefresh              -> still absent
  POST /Admin/Api/ParagraphSave  (any unrelated edit)  -> row now shows the PRE-SQL value
  ```
  **Never write `ItemType_*` via SQL on a live host.** `ParagraphSave` / `ItemFieldSave` are the only writes
  the cache stays coherent with; the field-by-field contract is in
  [`../../dw-demo-base/references/foundational/content-modelling.md`](../../dw-demo-base/references/foundational/content-modelling.md)
  §2.
- **Files and images are the exception.** `GetImage.ashx` keys its derived-image (resize/webp) cache on the
  **source file including its last-modified time**, so a multipart `POST /Admin/Api/Upload` with
  `allowOverwrite=true` rewrites the file, bumps its mtime, and invalidates the derived entries; the next
  request re-renders from the new source. Do **not** spend a `CacheInformationRefresh` sweep or wait for a
  recycle after an image overwrite. Verify by fetching the derived URL
  (`GetImage.ashx?image=…&width=…&format=webp`) and asserting the decoded dimensions match the new source's
  aspect ratio.

## Rebuilding the product index after a membership change

- **`BuildIndex` addresses the index FILE name and the named BUILD from the `.index` XML — the repository name
  alone `404`s.** The obvious argument shape fails in a way that reads as "the verb is unavailable", which is
  how a working verb gets written off:
  ```
  POST BuildIndex {Repository:"Products", IndexName:"Products.index", BuildName:"Full"}   -> ok
  POST BuildIndex {… IndexName:"Products"}      -> 404      # file name, not repository name
  POST BuildIndex {… BuildName:"Build Index"}   -> 404      # the build's name in the .index XML, not a label
  ```
  Read both values out of the `.index` file rather than composing them from what the admin screen displays.
- **A Full rebuild must target `Repository='Products'`.** `BuildIndex` with `Repository='ProductsFrontend'` or
  `'ProductsBackend'` (`IndexName=Products.index`, `BuildName=Full`) returns `status=ok` in under a second
  because it only **enqueues** — it does **not** refresh the **GroupID facet** that the `GroupID` filter of
  `QueryName=Products` reads. Only `Repository='Products'` runs the real synchronous Full rebuild, and it
  routinely exceeds a 120s client timeout; **that timeout is the expected shape of success, not a failure.**
- **`BuildIndex` is genuinely SYNCHRONOUS server-side, and the client timeout severs the RESPONSE, not the
  build.** A `Repository='Products'` Full build routinely exceeds a 120s client timeout — and the build then
  completes anyway. Reading the timeout as a failure and retrying is the expensive mistake: it queues a
  second full rebuild behind the one that was already succeeding. **Swallow the timeout and poll**
  `IndexStatusesAll` for completion. (Correcting an earlier reading that no index-status command existed on
  10.28.x: the *singular* `IndexStatus` and `GetIndexes` do answer `400 Unknown query`, which is what
  produced that conclusion — `IndexStatusesAll` is the verb that works, confirmed on 10.28.3 showing the
  build completing after the client had already given up.)
- **Verify the EFFECT on the Delivery API, never on the POST response.** Status tells you the build ran;
  only the query tells you it indexed what you wanted:
  `GET /dwapi/ecommerce/products/search?RepositoryName=Products&QueryName=Products&GroupID=<groupid>` →
  `totalProductsCount` per group, cross-checked against `GetCatalogGroupProducts`.
- **Re-run the `Repository='Products'` Full build after any recycle or 503 instance swap.** The facet can
  regress to a pre-expansion snapshot while DB relation truth stays correct — storefront PLPs and headless
  both under-render, and a repeat `ProductsFrontend`/`ProductsBackend` build has no effect on it. Scoping the
  builder to the demo's shop (`ShopsToIndex`) hardens against recurrence.

## Scheduled-task creation semantics (`TaskSaveCommand`)

For the tasks a demo legitimately owns — a demo clock, an ERP mock RESET runner. This is not a licence to
revive the SQL-through-a-task content-seeding motion retired above.

- **A recurring cadence is `RefreshEvery` (int) + `UnitOfTime` (`minute` / `hour` / `day`) — there is no
  `Schedule` string to set.** `RefreshEvery=1440, UnitOfTime=minute` reads back as *repeat every 1 day* with
  `nextRun` populated, and the host scheduler then fires it unattended. Confirm with `TaskById`: `schedule`,
  `refreshEvery`, `unitOfTime`, a populated `nextRun`, and `lastRunState=Success` advancing without a manual
  trigger.
- **A new daily task RE-ANCHORS to its first actual run, not to the `Begin` you set.** If `Begin` is earlier
  today, DW computes `nextRun` as a few minutes from now, fires once, and then keeps **that** accidental time
  forever — so a task created for an overnight slot quietly becomes a mid-afternoon task. **Set `Begin` to
  TOMORROW at the wanted wall-clock time when creating a daily task** (`RefreshEvery=1440`,
  `UnitOfTime=minute`), then read `TaskById(id).nextRun` back and assert it equals the intended slot. One
  affected task self-corrected only because a later `TasksMove` happened to re-save the row — not something to
  rely on.
- **Two companion shapes on the task family, both silent:** `TasksMove.Ids` is an array of **STRINGS** (integer
  ids are ignored, and the move reports success), and **`TaskToggleActive` TOGGLES rather than sets** — read
  `enabled` before and after, or a "make sure it's on" call turns it off.
- **`TaskRun` silently no-ops a DISABLED task from DW 10.28.3 onward.** Through 10.28.2 `TaskRun` executed a
  task created with `Enabled=false`; from 10.28.3 it does not, and reports `lastRunState=Exception` with an
  **empty** `lastLog` and `lastException` — a contentless failure that reads as a dead API. Create every task
  with `Enabled=true`. An ephemeral one-time task with `Begin` in the past and `Schedule=One time` never
  self-fires, so enabling it costs nothing.
- **`TaskSave` with `Id=0` CREATES A NEW TASK EVERY CALL — it is not an upsert.** A helper that posts
  `Id=0` on each invocation accretes one scheduled-task row per statement it ever ran. One install reached
  **1,463 tasks, 1,428 of them identical copies of a single SQL-runner** (a contiguous id block), which
  makes Settings → Scheduled tasks unusable as a demo screen and buries the handful of real tasks. **Create
  the runner ONCE, persist its id in the run ledger, and update in place** (`TaskSave` with the stored
  `Id`) on every subsequent call. Assert it: on a fresh demo, run ten statements through the helper and
  require the task count to grow by exactly **1**. An install already polluted needs a purge pass keyed on
  the task name, keeping the genuinely-owned tasks by id.
- **The SQL runner is WRITE-ONLY and DIAGNOSTIC-BLIND — there is no read channel back.** `Dw-RunSql`
  swallows batch errors: a failed batch reports `lastRunState=Exception` with `lastException` an **empty
  string**, the task model carries no `lastLog` member, and a `RAISERROR` peek is not surfaced anywhere
  either.
  ```
  pure SELECT + RAISERROR(N'PEEK<<%s>>', 10, 1, @v) WITH NOWAIT
    -> lastRunState = Exception,  lastException = "",  no lastLog member on the model
  ```
  So `SELECT` output cannot be read back and error text cannot be recovered. **Verify a batch by its
  API-visible EFFECT, never by task state text** — and treat "the task shows Exception" as carrying no
  information about *what* failed.
- **Enumerate tasks with `ScheduledTaskAll`, never a `/Tasks` page-walk.** `/Tasks` paging is backed by a
  factory that serves rows for **any** `PagingIndex`, including out-of-range ones, so `totalPages` is
  advisory and a naive walk collects duplicates without ever terminating cleanly — one recon pass collected
  **17,410 rows for a 1,463-row list**. `ScheduledTaskAll` returns the full list in one shot; cross-check
  its count against the DB before trusting either. Related: the sort enum is `Ascending` / `Descending` —
  `SortDirection=Asc` answers **400**.
- **A date-shifting task ("demo clock") has two extra rules that make a bare run useless as proof:** each
  shifter needs **its own anchor row** (the freshener re-anchors after computing its delta, so a second task
  reading the shared row sees delta 0 forever), and a new task creates its anchor on first execution, so the
  proof must be a **rewind-and-run**, never an install-then-run. Columns that a cancel/void/close operation
  overloads as a state marker need a per-column guard on top. Owned by
  [`dashboard-seeding.md`](dashboard-seeding.md) §8.
- **`TaskById` answers `400`, not `404`, for a missing id — an existence probe must treat ANY throw as
  absent.** The body is the generic `"Unable to load query parameters"`, indistinguishable from a
  malformed request, so a probe that only catches 404 misreads a deleted task as a broken call and stalls a
  cleanup pass. Probe with a try/catch that returns "absent" on any non-200.

## If you are diagnosing rows that were already SQL-seeded

The historical NOT-NULL column schema (why a hand-INSERTed `Page`/`GridRow`/`Paragraph`/`ItemType_*` row
renders wrong) is retained as a **forensic / teardown reference only** — not a seeding recipe — in
[`data-access.md`](../../dw-demo-base/references/foundational/data-access.md) "SQL-direct content seeding".
The post-mutation cache rules a direct write owes are in
[`../../dw-demo-base/references/foundational/cache-invalidation.md`](../../dw-demo-base/references/foundational/cache-invalidation.md).

## Cross-references

- [`templates.md`](templates.md) — `PageActive` vs `PageHidden` ("Hidden in Menu") page-state semantics.
- [`paragraphs.md`](paragraphs.md) — the empty-`ParagraphTemplate` alphabetical-fallback hazard and the
  `ProductListComponentSelector` cache rule.
