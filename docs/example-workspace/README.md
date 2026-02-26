# Example Workspace

This directory shows a realistic workspace layout for `wuhu-workspace-engine`.

## Structure

```
wuhu.yml                        # Configuration: defines the custom "project" kind
issues/
  0001.md                       # kind: issue, status: open, priority: high
  0002.md                       # kind: issue, status: closed, priority: medium
docs/
  architecture.md               # kind: document (explicit frontmatter, has tag property)
  getting-started.md            # kind: document (no frontmatter — title from heading)
projects/
  workspace-engine.md           # kind: project (custom kind), status: active
  native-apps.md                # kind: project, status: planning
```

## What This Demonstrates

| File | Kind Source | Title Source | Extra Properties |
|------|-----------|-------------|-----------------|
| `issues/0001.md` | `kind: issue` in frontmatter | `title:` in frontmatter | `status`, `priority` → `issues` table; `assignee` → `properties` only |
| `issues/0002.md` | `kind: issue` in frontmatter | `title:` in frontmatter | `resolution` → `properties` only (not a known issue property) |
| `docs/architecture.md` | `kind:` absent → defaults to `document` | `title:` in frontmatter | `tag` → `properties` table |
| `docs/getting-started.md` | No frontmatter → defaults to `document` | First `# Heading` | None |
| `projects/workspace-engine.md` | `kind: project` (custom kind from `wuhu.yml`) | `title:` in frontmatter | `status`, `priority`, `owner` → `projects` table; `milestone` → `properties` only |
| `projects/native-apps.md` | `kind: project` | `title:` in frontmatter | `platform` → `properties` only |

## After Scanning

If you scan this workspace:

```swift
let root = URL(fileURLWithPath: ".../docs/example-workspace")
let scanner = WorkspaceScanner(root: root)
let config = try scanner.loadConfiguration()
let engine = try WorkspaceEngine(configuration: config)
try scanner.scan(into: engine)
```

The engine will have:

- **`docs` table**: 7 rows (6 markdown files + this README)
- **`issues` table**: 2 rows (status, priority columns)
- **`projects` table**: 2 rows (status, priority, owner columns)
- **`properties` table**: rows for every frontmatter key-value pair across all files

Example queries:

```sql
-- All open issues
SELECT d.path, d.title, i.status FROM docs d
JOIN issues i ON d.path = i.path WHERE i.status = 'open';

-- Active projects and their owners
SELECT d.title, p.owner FROM docs d
JOIN projects p ON d.path = p.path WHERE p.status = 'active';

-- All documents with a tag (via properties table)
SELECT d.path, d.title, pr.value as tag FROM docs d
JOIN properties pr ON d.path = pr.path WHERE pr.key = 'tag';

-- Documents where 'milestone' is set (regardless of kind)
SELECT d.path, d.kind, pr.value as milestone FROM docs d
JOIN properties pr ON d.path = pr.path WHERE pr.key = 'milestone';
```
