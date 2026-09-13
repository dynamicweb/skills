# Writing the SQL itself: column shapes, batches, truncation and transport

Traps in the `SQL` statement and in the script that carries it, distinct from the cache debt it owes. Everything here applies to the
**direct SQL** rung only — local installs, after MCP and the Management API have been shown not to
reach the operation — and every recipe still owes the flush or restart in
[`cache-invalidation.md`](cache-invalidation.md).

## Contents

- [An XML column that is typed nvarchar](#an-xml-column-that-is-typed-nvarchar)
- [A rolled-back dry run still burns IDENTITY values](#a-rolled-back-dry-run-still-burns-identity-values)
- [A batch is compiled as a whole](#a-batch-is-compiled-as-a-whole)
- [Two silent truncations](#two-silent-truncations)
- [T-SQL block comments nest](#t-sql-block-comments-nest)
- [A reserved column name and an inclusive sequence restart](#a-reserved-column-name-and-an-inclusive-sequence-restart)
- [A /Files path passed as a Git Bash argument](#a-files-path-passed-as-a-git-bash-argument)

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

## A batch is compiled as a whole

SQL Server compiles every statement in a batch before it executes the first one, and a column or
table that does not exist yet cannot be bound. A script that creates or alters a table and then
names the new column in the same batch fails with `Invalid column name '<the column you are
adding>'`, and the `ALTER` or `CREATE` above it **never runs**, so the error reads as a typo rather
than as an ordering problem.

- **Run by `sqlcmd` or an editor:** put `GO` between the DDL and any statement that depends on it.
  `GO` is a client-tool batch separator, not T-SQL.
- **Run as one command inside one transaction** (the prove-then-commit shape, where a column add
  and its seed are proven together by a rolled-back run): `GO` is not available, so wrap the
  `ALTER` and **every statement that names the new column in `EXEC()`**, which defers name
  resolution to execution time:

```sql
BEGIN TRANSACTION;
EXEC('ALTER TABLE dbo.MyTable ADD TransitDays int NOT NULL CONSTRAINT DF_MyTable_TransitDays DEFAULT(1)');
EXEC('UPDATE dbo.MyTable SET TransitDays = 2 WHERE Code = ''NORTH''');
EXEC('IF EXISTS (SELECT 1 FROM dbo.MyTable WHERE TransitDays NOT BETWEEN 1 AND 5)
          THROW 50001, ''ASSERT FAIL: TransitDays out of range'', 1;');
ROLLBACK TRANSACTION;  -- COMMIT once the dry run holds
```

The step that catches people twice: **the assertions go inside `EXEC()` too.** An assertion naming
the new column is exactly as unresolvable as the `UPDATE`, so a file fixed by wrapping only the
writes still fails to compile.

## Two silent truncations

A column that is too small refuses the write with `String or binary data would be truncated`, which
teaches everyone to expect an error. Two other paths truncate **without an error or a warning**,
so "the row exists" and "1 row affected" are both true on the damaged value.

**A chain of `N''` literals is `nvarchar(4000)`.** An nvarchar literal is `nvarchar(n)` with
`n <= 4000`, so literals joined with `+` form an `nvarchar(4000)` expression. The value is cut while
it is being built, before it is assigned, so an `nvarchar(max)` target column does not save it.
Long content is chunked into literals in the first place because `sqlcmd` truncates very long input
lines, so the workaround for one limit walks into the other. Promote the expression by casting the
**first** chunk:

```sql
UPDATE ItemType_MyText
   SET Text = CAST(N'<div>first chunk ...' AS nvarchar(max))
            + N'... second chunk ...'
            + N'... last chunk</div>'
 WHERE Id = @id;
```

**A `DECLARE` or `SET` into a too-small `nvarchar` variable truncates silently.** The same value
into a too-small column raises the error; into a variable it loses its tail. When the tail is the
end of a structural fragment (a settings prefix ending `name="Activity" value="`), the result is
still well-formed XML, so every syntactic check passes. Size variables generously, or use
`nvarchar(max)`.

**Assert on content, not on shape.** After any long or structured SQL-written value:

- compare `LEN(column)` with the source length;
- check that the fragment the value exists to carry is present, for example
  `CHARINDEX('name="Activity" value="', TaskAddInSettings) > 0`, or the closing sentence of an
  article in the rendered page;
- never accept "it parses" as the check: a truncated fragment can still parse.

## T-SQL block comments nest

Unlike C, C# and JavaScript, **T-SQL `/* ... */` comments nest.** A `/*` inside a block comment opens
a second comment, the `*/` meant to close the first closes the inner one, and every statement after
it is swallowed as comment text. The error is `Missing end comment mark '*/'`, reported against the
batch with no line number, and counting delimiters does not find it because they are balanced.

The usual trigger is prose in a header comment that names a glob or a wildcard path:

```sql
/* The tables themselves are dropped by tables/*.revert.sql. */   -- breaks the whole file
-- The tables themselves are dropped by the per-table revert scripts.  -- safe
```

**Never write a glob, a wildcard path or any `/*` sequence inside a block comment.** Use `--` line
comments for anything that contains a path.

## A reserved column name and an inclusive sequence restart

- **`LineNo` is a reserved word.** `CREATE TABLE ... ( LineNo int ... )` fails with
  `Incorrect syntax near the keyword 'LineNo'`. Name the column `LineNumber` rather than
  bracket-quoting it everywhere it is used.
- **`ALTER SEQUENCE ... RESTART WITH n` makes `n` the next value.** Afterwards
  `sys.sequences.current_value` reads `n` **and** the next `NEXT VALUE FOR` returns `n`. An
  assertion on "the next number to be issued" reads `sys.sequences.current_value` after a restart,
  with no `+ 1`. Once a value has been drawn, it holds the last value issued, so the same assertion
  needs the increment added. Do not probe by drawing a value inside a rolled-back transaction:
  like IDENTITY, a sequence draw is not undone by the rollback.

## A /Files path passed as a Git Bash argument

**Git Bash rewrites a leading `/Files/...` argument before the receiving program sees it.** The
MSYS layer treats a value that starts with `/` as a POSIX path needing translation and prefixes the
Git installation's own path, so `/Files/Images/hero.png` arrives as
`C:/Program Files/Git/Files/Images/hero.png`. A script that takes the path as an argument and
writes it into an item field, a SQL variable or an API payload stores the corrupted value, and
nothing fails.

- **Pass Dynamicweb paths in a JSON payload file** the script reads, or through an MCP tool call,
  never as a shell argument; values read from a file are not rewritten.
- Where an argument is unavoidable, set `MSYS_NO_PATHCONV=1` for that command.
- Read the stored value back after the write: the corruption is visible only in the data.
