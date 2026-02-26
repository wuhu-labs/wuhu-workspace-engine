# wuhu-workspace-engine

Workspace query engine for [Wuhu](https://github.com/wuhu-labs/wuhu) — scans
Markdown files, parses YAML frontmatter, indexes into SQLite, and supports
structured queries.

## Targets

| Target | Description | Dependencies |
|--------|-------------|--------------|
| `WorkspaceContracts` | Types and protocols (client-safe, no external deps) | None |
| `WorkspaceEngine` | SQLite query engine (pure, no filesystem) | WorkspaceContracts, GRDB |
| `WorkspaceScanner` | File discovery, frontmatter parsing, filesystem watching | WorkspaceContracts, WorkspaceEngine, Yams |

## Adding as a Dependency

```swift
.package(url: "https://github.com/wuhu-labs/wuhu-workspace-engine.git", from: "0.1.0")
```

Import only what you need:

```swift
// iOS app — just the types
.product(name: "WorkspaceContracts", package: "wuhu-workspace-engine")

// Server — the full engine
.product(name: "WorkspaceEngine", package: "wuhu-workspace-engine")
.product(name: "WorkspaceScanner", package: "wuhu-workspace-engine")
```

## Data Model

Every Markdown file in the workspace is indexed into an in-memory SQLite database:

- **`docs`** — universal registry (`path TEXT PK`, `kind TEXT`, `title TEXT`) for every document
- **Kind tables** — extension tables with kind-specific columns (e.g., `issues` has `status`, `priority`). Table name = kind + "s".
- **`properties`** — key-value table (`path`, `key`, `value`) for *all* frontmatter. Even properties that also live in a kind table are duplicated here, enabling uniform ad-hoc queries.

Kinds are defined in `wuhu.yml` at the workspace root. Built-in kinds: `document`, `issue`.

## Quick Start

### Scan a workspace

```swift
import WorkspaceEngine
import WorkspaceScanner

// 1. Load configuration (reads wuhu.yml for custom kinds).
let root = URL(fileURLWithPath: "/path/to/workspace")
let scanner = WorkspaceScanner(root: root)
let config = try scanner.loadConfiguration()

// 2. Create engine with the configuration.
let engine = try WorkspaceEngine(configuration: config)

// 3. Scan — discovers .md files, parses frontmatter, populates the engine.
try scanner.scan(into: engine)
```

### Query documents

```swift
// All documents, sorted by path.
let all = try engine.allDocuments()

// Only issues.
let issues = try engine.documents(where: .issue)

// Single document by path.
if let doc = try engine.document(at: "issues/0001.md") {
    print(doc.title ?? "untitled")       // from frontmatter or first # heading
    print(doc.kind)                       // e.g. "issue"
    print(doc.properties["status"] ?? "") // e.g. "open"
}
```

### Raw SQL queries

`rawQuery` returns `[[String: String]]` — each row is a dictionary of column
names to string values (NULLs are omitted).

```swift
// Open issues via the kind extension table.
let openIssues = try engine.rawQuery("""
    SELECT d.path, d.title, i.status, i.priority
    FROM docs d
    JOIN issues i ON d.path = i.path
    WHERE i.status = 'open'
""")

// Documents with a specific property (via the properties table).
let tagged = try engine.rawQuery("""
    SELECT d.path, d.title
    FROM docs d
    JOIN properties p ON d.path = p.path
    WHERE p.key = 'tag' AND p.value = 'important'
""")

// Count documents by kind.
let counts = try engine.rawQuery("""
    SELECT kind, COUNT(*) as count FROM docs GROUP BY kind
""")
```

### File watching

`watch(engine:)` performs an initial scan, then keeps the engine in sync as
files are created, modified, or deleted. It runs until the task is cancelled.

```swift
let task = Task {
    try await scanner.watch(engine: engine)
}

// ... later ...
task.cancel()
```

On macOS the watcher uses FSEvents (CoreServices). On Linux it uses inotify.
Both implementations coalesce rapid events and trigger a full rescan on overflow
(e.g., after `git checkout` changes many files at once).

### Custom kinds in `wuhu.yml`

```yaml
kinds:
  - kind: project
    properties:
      - status
      - priority
      - owner
  - kind: recipe
    properties:
      - cuisine
      - difficulty
      - servings
```

Each custom kind gets its own extension table (e.g., `projects`, `recipes`) with
the listed properties as TEXT columns. You can then query them just like the
built-in `issues` table:

```swift
let config = try scanner.loadConfiguration()
let engine = try WorkspaceEngine(configuration: config)
try scanner.scan(into: engine)

let active = try engine.rawQuery("""
    SELECT d.path, d.title, p.owner
    FROM docs d
    JOIN projects p ON d.path = p.path
    WHERE p.status = 'active'
""")
```

Built-in kinds (`document`, `issue`) are always available. If you list a built-in
kind in `wuhu.yml`, your definition replaces the default (e.g., to add extra
columns to `issues`).

## Example Workspace

See [`docs/example-workspace/`](docs/example-workspace/) for a realistic workspace
layout demonstrating custom kinds, frontmatter conventions, and title extraction.

## Query Cookbook

See [`USAGE.md`](USAGE.md) for more SQL examples against the indexed data.

## License

Apache 2.0 — see [LICENSE](LICENSE).
