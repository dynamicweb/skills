---
name: dw-data-access
type: knowledge
group: data
description: 'Choose appropriate data-access patterns and optimize caching in Dynamicweb 10. Triggers: data access, API vs SQL, cache invalidation, SQL gotchas. Non-triggers: C# API usage -> dw-extend-csharp-api; specific domain logic -> domain-specific skills.'
---

# Data Access in Dynamicweb 10

## When to Use the Service API vs Raw SQL

| Use case | Approach |
|----------|----------|
| Reading/writing Ecommerce, Content, User data | **Service API** — handles caching, notification firing, type safety |
| Custom tables you own | **`Database` static class** — direct SQL for custom data |
| Reporting / large aggregate queries | **`Database` static class** — services load full objects; SQL is more efficient for aggregates |
| Cross-domain joins not possible via API | **`Database` static class** with read-only queries |

**Use the Service API for writes to Ecommerce core tables** (EcomProducts, EcomOrders, etc.), never raw SQL — raw SQL bypasses cache invalidation and notification subscribers.

## Database Static Class

`Dynamicweb.Data.Database` provides the SQL access layer. All methods accept either a raw SQL string or a `CommandBuilder`.

### Reading with a DataReader

```csharp
using Dynamicweb.Data;

var cb = new CommandBuilder();
cb.Add("SELECT PageID, PageName FROM Page WHERE PageActive = {0}", true);

using IDataReader dr = Database.CreateDataReader(cb);
while (dr.Read())
{
    int id = Converter.ToInt32(dr["PageID"]);
    string name = dr["PageName"]?.ToString() ?? "";
}
```

### Reading into a DataSet

```csharp
var cb = new CommandBuilder();
cb.Add("SELECT * FROM MyCustomTable WHERE Status = {0}", "Active");
DataSet ds = Database.CreateDataSet(cb);

foreach (DataRow row in ds.Tables[0].Rows)
{
    string value = row["ColumnName"]?.ToString() ?? "";
}
```

### Scalar Query

```csharp
var cb = new CommandBuilder();
cb.Add("SELECT COUNT(*) FROM EcomProducts WHERE ProductActive = {0}", true);
int count = Converter.ToInt32(Database.ExecuteScalar(cb));
```

### Write (Insert / Update / Delete)

```csharp
var cb = new CommandBuilder();
cb.Add("INSERT INTO MyCustomTable (Name, CreatedAt) VALUES ({0}, {1})", "Test", DateTime.UtcNow);
Database.ExecuteNonQuery(cb);
```

### CommandBuilder Parameter Syntax

`CommandBuilder` uses positional `{0}`, `{1}`, … placeholders that are mapped to parameterized SQL (`@p0`, `@p1`, …) — **never string-interpolated**, so SQL injection is not possible:

```csharp
cb.Add("WHERE Name LIKE {0}", "%" + searchTerm + "%"); // Safe: searchTerm goes as @p0
```

Multiple `Add()` calls append to the same SQL string:

```csharp
var cb = new CommandBuilder();
cb.Add("SELECT * FROM MyCustomTable");
cb.Add(" WHERE Active = {0}", true);
if (filterByName)
    cb.Add(" AND Name = {0}", name);
cb.Add(" ORDER BY CreatedAt DESC");
```

### Using `Converter` for Safe Type Conversion

`Dynamicweb.Converter` handles null values and type coercions from `DataReader` columns:

```csharp
int id = Converter.ToInt32(dr["MyInt"]);       // null → 0
bool flag = Converter.ToBoolean(dr["MyBit"]);  // null → false
double val = Converter.ToDouble(dr["MyDecimal"]);
DateTime dt = Converter.ToDateTime(dr["MyDate"]);
```

## Caching

`Dynamicweb.Caching.Cache.Current` implements `ICacheManager` and provides the platform cache shared across all modules.

### Basic Cache Read-Through Pattern

```csharp
using Dynamicweb.Caching;

const string cacheKey = "MyCompany.MyKey";

if (!Cache.Current.TryGet(cacheKey, out MyObject? value))
{
    value = LoadExpensiveData();
    Cache.Current.Set(cacheKey, value, CacheItemPolicy.DefaultStoragePolicy);
}

return value;
```

### Cache Policies

| Policy | Expiry |
|--------|-------|
| `CacheItemPolicy.DefaultStoragePolicy` | 10 minutes sliding expiration |
| `new CacheItemPolicy { SlidingExpiration = TimeSpan.FromMinutes(n) }` | Custom sliding |
| `new CacheItemPolicy { AbsoluteExpiration = DateTimeOffset.UtcNow.AddHours(1) }` | Absolute expiration |

### Cache Invalidation

```csharp
Cache.Current.Remove(cacheKey);
```

Invalidate on data change — subscribe to a notification (e.g., `Standard.Page.Saved`) and remove the relevant cache key in `OnNotify`. See [dw-extend-providers](../dw-extend-providers).

### Cache Key Design

Use namespaced keys to avoid collision between modules:

```csharp
string key = $"MyCompany.Products.{languageId}.{groupId}";
```

## Transactions

```csharp
using Dynamicweb.Data;

using var transaction = Database.CreateTransaction();
try
{
    var cb1 = new CommandBuilder();
    cb1.Add("UPDATE MyTable SET Status = {0} WHERE ID = {1}", "Done", id1);
    Database.ExecuteNonQuery(cb1, transaction);

    var cb2 = new CommandBuilder();
    cb2.Add("INSERT INTO MyLog (Message) VALUES ({0})", "Updated");
    Database.ExecuteNonQuery(cb2, transaction);

    transaction.Commit();
}
catch
{
    transaction.Rollback();
    throw;
}
```

## Pitfalls

**Never use `Dynamicweb.Data.Database` for Ecommerce core writes** — use `Dynamicweb.Ecommerce.Services.Products.Save(product)`, `Orders.Save(order)`, etc. Raw SQL bypasses caching and notification subscribers.

**Don't use string interpolation for SQL** — always use `CommandBuilder` parameters. String concatenation enables SQL injection.

**`DataReader` must be disposed** — always wrap with `using`. Failing to dispose holds the DB connection open.

**`DataSet` for large result sets is expensive** — prefer `CreateDataReader` for high-volume reads; `CreateDataSet` loads everything into memory.

**Context.Current is null in scheduled tasks** — the `Database` static class works fine in background tasks; no request context is needed.

**Column names are case-sensitive** — `dr["PageID"]` and `dr["Pageid"]` are different. Always use the exact column name as defined in the DB schema.

## Next Steps

- **Need to call Dynamicweb domain APIs?** See [dw-extend-csharp-api](../dw-extend-csharp-api)
- **Running SQL on a schedule?** See [dw-extend-scheduled-tasks](../dw-extend-scheduled-tasks)
- **Invalidating cache from a notification?** See [dw-extend-providers](../dw-extend-providers)
