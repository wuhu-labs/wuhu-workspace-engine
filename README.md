# wuhu-workspace-engine

Workspace query engine for [Wuhu](https://github.com/wuhu-labs/wuhu) — scans
Markdown files, parses YAML frontmatter, indexes into SQLite, and supports
structured queries.

## Targets

| Target | Description | Dependencies |
|--------|-------------|--------------|
| `WorkspaceContracts` | Types and protocols (client-safe) | None |
| `WorkspaceEngine` | SQLite query engine (pure, no filesystem) | WorkspaceContracts, GRDB |
| `WorkspaceScanner` | File discovery, frontmatter parsing, fswatch | WorkspaceContracts, WorkspaceEngine, Yams |

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

- **`docs`** — universal registry (path, kind, title) for every document
- **Kind tables** — extension tables with kind-specific columns (e.g., `issues` has `status`, `priority`)
- **`properties`** — key-value table for all frontmatter (including known properties, for uniform querying)

Kinds are defined in `wuhu.yml` at the workspace root. Built-in kinds: `document`, `issue`.

## Quick Start

```swift
import WorkspaceEngine
import WorkspaceScanner

// Create engine (in-memory)
let engine = WorkspaceEngine()

// Scan a workspace directory
let scanner = WorkspaceScanner(root: "/path/to/workspace", engine: engine)
try await scanner.scan()

// Query
let openIssues = try engine.query("SELECT * FROM issues WHERE status = 'open'")
```

## License

Apache 2.0 — see [LICENSE](LICENSE).
