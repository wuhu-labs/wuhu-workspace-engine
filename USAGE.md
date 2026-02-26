# Query Cookbook

Concrete SQL examples you can run with `engine.rawQuery(...)` against the indexed
workspace data.

All examples assume a workspace has been scanned into the engine. See
[README.md](README.md) for setup.

## Basics

### All documents

```sql
SELECT path, kind, title FROM docs ORDER BY path
```

### Count documents by kind

```sql
SELECT kind, COUNT(*) as count FROM docs GROUP BY kind ORDER BY count DESC
```

### Find a document by path

```sql
SELECT * FROM docs WHERE path = 'issues/0001.md'
```

### Search titles

```sql
SELECT path, title FROM docs WHERE title LIKE '%workspace%'
```

## Kind Extension Tables

Each kind with known properties gets an extension table named `<kind>s`
(e.g., `issues`, `projects`, `recipes`). These tables have a `path` column
that is a foreign key back to `docs`.

### All open issues

```sql
SELECT d.path, d.title, i.status, i.priority
FROM docs d
JOIN issues i ON d.path = i.path
WHERE i.status = 'open'
```

### Issues sorted by priority

```sql
SELECT d.path, d.title, i.priority, i.status
FROM docs d
JOIN issues i ON d.path = i.path
ORDER BY
  CASE i.priority
    WHEN 'critical' THEN 0
    WHEN 'high' THEN 1
    WHEN 'medium' THEN 2
    WHEN 'low' THEN 3
    ELSE 4
  END
```

### Custom kind: active projects

Assuming `wuhu.yml` defines a `project` kind with `status`, `priority`, `owner`:

```sql
SELECT d.path, d.title, p.status, p.owner
FROM docs d
JOIN projects p ON d.path = p.path
WHERE p.status = 'active'
ORDER BY d.title
```

### Custom kind: Italian recipes

Assuming `wuhu.yml` defines a `recipe` kind with `cuisine`, `difficulty`, `servings`:

```sql
SELECT d.path, d.title, r.difficulty, r.servings
FROM docs d
JOIN recipes r ON d.path = r.path
WHERE r.cuisine = 'Italian'
```

## The Properties Table

The `properties` table stores **all** frontmatter key-value pairs (except `kind`
and `title`, which live on `docs`). This includes properties that also appear in
kind extension tables. It enables uniform queries without knowing the kind.

Schema: `path TEXT, key TEXT, value TEXT` — primary key is `(path, key)`.

### Find documents with a specific property value

```sql
SELECT d.path, d.title
FROM docs d
JOIN properties p ON d.path = p.path
WHERE p.key = 'tag' AND p.value = 'important'
```

### Find documents that have a specific property (any value)

```sql
SELECT d.path, d.title, p.value as assignee
FROM docs d
JOIN properties p ON d.path = p.path
WHERE p.key = 'assignee'
```

### All properties for a single document

```sql
SELECT key, value FROM properties WHERE path = 'issues/0001.md' ORDER BY key
```

### Pivot: documents with their status (any kind)

```sql
SELECT d.path, d.kind, d.title, p.value as status
FROM docs d
JOIN properties p ON d.path = p.path
WHERE p.key = 'status'
ORDER BY d.path
```

### Count distinct values for a property

```sql
SELECT p.value as status, COUNT(*) as count
FROM properties p
WHERE p.key = 'status'
GROUP BY p.value
ORDER BY count DESC
```

## Cross-Kind Queries

Because the `properties` table is universal, you can query across kinds:

### All documents with status = 'open' (issues, projects, anything)

```sql
SELECT d.path, d.kind, d.title
FROM docs d
JOIN properties p ON d.path = p.path
WHERE p.key = 'status' AND p.value = 'open'
```

### Documents with multiple property conditions

```sql
SELECT d.path, d.title
FROM docs d
JOIN properties p1 ON d.path = p1.path AND p1.key = 'status' AND p1.value = 'open'
JOIN properties p2 ON d.path = p2.path AND p2.key = 'priority' AND p2.value = 'high'
```

## Documents by Directory

Paths are workspace-relative, so you can filter by directory prefix:

```sql
SELECT path, title FROM docs WHERE path LIKE 'issues/%' ORDER BY path
```

```sql
SELECT path, title FROM docs WHERE path LIKE 'docs/%' ORDER BY path
```

## Using `rawQuery` in Swift

```swift
let rows = try engine.rawQuery("""
    SELECT d.path, d.title, i.status
    FROM docs d
    JOIN issues i ON d.path = i.path
    WHERE i.status = 'open'
""")

for row in rows {
    // row is [String: String] — column name → string value.
    // NULLs are omitted from the dictionary.
    print("\(row["path"]!): \(row["title"] ?? "untitled") [\(row["status"]!)]")
}
```

For mutating SQL (e.g., creating indexes), use `rawExecute`:

```swift
try engine.rawExecute("""
    CREATE INDEX IF NOT EXISTS idx_properties_key ON properties(key)
""")
```
