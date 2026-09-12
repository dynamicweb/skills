# Writing the SQL itself: column shapes and transaction behaviour

Traps in the `SQL` statement, distinct from the cache debt it owes. Everything here applies to the
**direct SQL** rung only — local installs, after MCP and the Management API have been shown not to
reach the operation — and every recipe still owes the flush or restart in
[`cache-invalidation.md`](cache-invalidation.md).

## Contents

- [An XML column that is typed nvarchar](#an-xml-column-that-is-typed-nvarchar)
- [A rolled-back dry run still burns IDENTITY values](#a-rolled-back-dry-run-still-burns-identity-values)

## An XML column that is typed nvarchar

`Paragraph.ParagraphModuleSettings` stores an XML document in an **`nvarchar(max)`** column. Read it
cast to a string, edit it as a string, and write the string straight back — **no `xml` typing
anywhere in the statement**:

```sql
SELECT CAST(ParagraphModuleSettings AS nvarchar(max)) FROM Paragraph WHERE ParagraphId = @p;
-- edit the value as text
UPDATE Paragraph SET ParagraphModuleSettings = @s WHERE ParagraphId = @p;
```

The instinct to use the `xml` type on a column whose contents are unmistakably XML is exactly what
breaks it: `SET ParagraphModuleSettings = CONVERT(xml, @s)` makes the right-hand side `xml`-typed,
which SQL Server then refuses to assign back to `nvarchar`, with an error that reads backwards —
`Implicit conversion from data type xml to nvarchar(max) is not allowed`.

Two riders:

- **A SQL edit here must be the last write to that paragraph.** The next `ParagraphSave` on it —
  MCP or Admin API — rewrites module settings from the paragraph cache and reverts the edit. See
  "Mixing MCP and SQL on the same rows" in [`cache-invalidation.md`](cache-invalidation.md).
- The same error shape appears on any column whose declared type and apparent content disagree;
  check `sys.columns` before adding a `CONVERT` on either side.

## A rolled-back dry run still burns IDENTITY values

**Treat every IDENTITY value printed by a rolled-back run as invalid.** IDENTITY allocation is not
transactional: the rollback undoes the rows and not the counter, so a dry run that prints new ids
4, 5, 6, 7 produces 8, 9, 10, 11 when the same file is committed seconds later. Everything downstream
that copied an id from the dry-run output — the follow-up script, the runbook, the register — is
wrong, and nothing failed.

This is correct, documented database behaviour, and it is still a trap here because the
prove-then-commit idiom actively invites reading ids off the dry run: the dry run exists so its
output can be inspected. The worse version is silent — when nothing else inserted in between, the two
runs agree and the habit is reinforced until the day they do not.

**Write the batch so no generated id is ever named:**

- capture each id into a variable with `SCOPE_IDENTITY()` and use the variable for the child rows;
- assert on **counts and relationships**, never on a literal id number;
- where a downstream step needs the ids, read them back **after** the commit, by the natural key.

A batch shaped that way is unaffected by the gap — only a reader of the dry-run output is misled,
which is exactly who the dry run is for.

Reseeding the identity to close the gap is not worth a write against a platform table, and
`IDENTITY_INSERT` is worse: the platform's own insert path does not use it, and matching that path is
what keeps the rows indistinguishable from ones the admin UI would have made.
