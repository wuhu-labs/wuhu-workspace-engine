# AGENTS.md

## What is wuhu-workspace-engine

A workspace query engine for Wuhu. Scans Markdown files in a workspace directory,
parses their YAML frontmatter, indexes everything into an in-memory SQLite database
(via GRDB), and supports structured queries and live observation.

## Architecture

Three targets with clear dependency boundaries:

### WorkspaceContracts

Pure types and protocols. **No external dependencies.** Safe to import from iOS
apps or any other client — never pulls in GRDB or filesystem code.

Public types:
- `Kind` — identifies a document kind (e.g., `"document"`, `"issue"`). `RawRepresentable<String>`, `ExpressibleByStringLiteral`. Built-in statics: `.document`, `.issue`.
- `DocumentRecord` — a row in the `docs` table: `path` (PK), `kind`, `title?`.
- `PropertyRecord` — a row in the `properties` table: `path`, `key`, `value`.
- `WorkspaceDocument` — a fully-loaded document: its `DocumentRecord` + all properties as `[String: String]`. Convenience accessors: `.path`, `.kind`, `.title`.
- `KindDefinition` — describes a kind and its known property keys (columns in the extension table). Built-in statics: `.document` (no properties), `.issue` (status, priority).
- `WorkspaceConfiguration` — parsed shape of `wuhu.yml`: an array of `KindDefinition`s and an array of `Rule`s. Static `.empty` for no custom kinds or rules.
- `Rule` — a path-based rule: `path` (glob pattern) and `kind` (Kind). Used to assign kinds based on directory structure when frontmatter doesn't specify one.

### WorkspaceEngine

Pure SQLite-backed query engine. Owns the database. **No filesystem knowledge.**

Public API on `WorkspaceEngine` (a `Sendable` final class):
- `init(configuration:) throws` — in-memory database.
- `init(path:configuration:) throws` — file-backed database.
- `upsertDocument(_:properties:) async throws` — insert or replace a document + properties + kind extension row.
- `removeDocument(at:) async throws` — delete by path (cascades to properties and kind extension).
- `removeAllDocuments() async throws` — clear everything.
- `allDocuments() async throws -> [WorkspaceDocument]` — all documents, sorted by path.
- `documents(where:) async throws -> [WorkspaceDocument]` — filter by kind.
- `document(at:) async throws -> WorkspaceDocument?` — single document by path.
- `rawQuery(_:) async throws -> [[String: String]]` — arbitrary SELECT. Each row = `[columnName: stringValue]`, NULLs omitted.
- `rawExecute(_:) async throws` — arbitrary mutating SQL.
- `observeAllDocuments() -> AsyncValueObservation<[WorkspaceDocument]>` — GRDB observation, fires on any docs/properties change.
- `observeDocuments(where:) -> AsyncValueObservation<[WorkspaceDocument]>` — GRDB observation filtered by kind.
- `kindDefinitions: [KindDefinition]` — the resolved definitions used for the schema.

All public read/write methods are `async throws`, using GRDB's async `DatabaseQueue`
overloads. This frees the calling cooperative thread while SQLite work runs on
GRDB's dedicated `SerialExecutor`-backed `DispatchQueue`. Initialization
(`init`) remains synchronous since schema creation must complete before the
engine is usable.

Schema created on init:
1. `docs` table — `path TEXT PK`, `kind TEXT NOT NULL DEFAULT 'document'`, `title TEXT`.
2. `properties` table — `path TEXT FK`, `key TEXT`, `value TEXT`, PK = `(path, key)`.
3. One extension table per kind that has known properties — table name = `kind.rawValue + "s"` (e.g., `issues`, `recipes`). Columns: `path TEXT PK FK` + one `TEXT` column per property.

### WorkspaceScanner

The impure side. Discovers files, parses frontmatter, watches for changes, feeds
updates into the engine.

Public types and API:
- `WorkspaceScanner` — main entry point.
  - `init(root: URL)` — root URL of the workspace directory.
  - `loadConfiguration() throws -> WorkspaceConfiguration` — reads `wuhu.yml` at the root.
  - `discoverFiles() throws -> [URL]` — recursively finds `.md` files (skips `.git`, `.build`, `.hidden`, `node_modules`).
  - `parseFile(at:rules:) throws -> (record: DocumentRecord, properties: [String: String])` — reads and parses a single file. Optional `rules` parameter for path-based kind assignment.
  - `parseContent(_:path:) -> (record: DocumentRecord, properties: [String: String])` — pure, no filesystem (static method).
  - `parseContent(_:path:rules:) -> (record: DocumentRecord, properties: [String: String])` — pure, with path-based rules for kind fallback (static method).
  - `scan(into:) async throws` — full scan: discover + parse + populate engine (clears existing data first). Loads configuration and applies path-based rules. **Async.**
  - `watch(engine:) async throws` — initial scan + live FSEvents/inotify watching. Runs until task is cancelled.

- `FrontmatterParser` — enum with static methods:
  - `parse(_:) -> ParsedFrontmatter` — extracts YAML frontmatter from Markdown. Returns `fields: [String: String]` (top-level scalar values only; nested structures are skipped) and `body: String`.
  - `extractHeadingTitle(from:) -> String?` — finds the first `# Heading` in the body.

- `ConfigurationLoader` — enum with static methods:
  - `loadConfiguration(from:) throws -> WorkspaceConfiguration` — reads `wuhu.yml`. Returns `.empty` if the file doesn't exist.
  - `parseConfiguration(_:) throws -> WorkspaceConfiguration` — parses a YAML string. Handles both `kinds` and `rules` sections.

- `FileDiscovery` — enum with static methods:
  - `discoverMarkdownFiles(in:) throws -> [URL]` — recursive `.md` discovery, sorted by relative path.
  - `relativePath(of:to:) -> String` — computes workspace-relative path.

- `GlobMatcher` — enum with static methods:
  - `matches(pattern:path:) -> Bool` — matches a path against a glob pattern. Supports `*` (within segment) and `**` (across segments). Uses `fnmatch(3)` under the hood.

- `FileWatcher` — watches a directory tree for filesystem changes.
  - `init(root: URL)` — resolves symlinks via `realpath(3)`.
  - `start() -> AsyncStream<FileWatchEvent>` — begins monitoring. Only one stream at a time.
  - `stop()` — tears down the watcher and finishes the stream.
  - On **macOS**: FSEvents (CoreServices) with 100ms latency, file-level events, no-defer flag.
  - On **Linux**: inotify with recursive watch descriptors, 200ms poll interval, pipe-based stop signal.

- `FileWatchEvent` — `.created(path:)`, `.modified(path:)`, `.deleted(path:)`, `.scanRequired`.

## Data Model

- **`docs` table**: Universal registry. Every document lands here (path, kind, title).
- **Kind tables** (e.g., `issues`): Extension tables with kind-specific columns.
  `path` is the FK back to `docs` with `ON DELETE CASCADE`.
- **`properties` table**: Key-value catch-all (`path`, `key`, `value`). ALL
  frontmatter is duplicated here (except `kind` and `title`, which are extracted
  into `docs`), even if it also lives in a kind table. This enables uniform
  ad-hoc queries without knowing which kind table to join.

Kinds are defined in `wuhu.yml`. Built-in kinds: `document` (no extension table,
since it has no properties), `issue` (extension table `issues` with `status`,
`priority`).

## Path-Based Rules

Documents can get their `kind` from three sources (in priority order):
1. **Frontmatter** — `kind: issue` in the YAML frontmatter always wins.
2. **Path rules** — `rules` in `wuhu.yml` match glob patterns against the
   document's workspace-relative path. First match wins.
3. **Default** — `.document` if nothing else matches.

Example `wuhu.yml`:
```yaml
rules:
  - path: "issues/**"
    kind: issue
  - path: "docs/architecture/**"
    kind: architecture
```

## Local Dev

### Prerequisites

- Swift 6.2 toolchain
- macOS 14+ or Linux (Ubuntu 24.04 / Noble recommended)

### Build & Test

```bash
swift build
swift test
```

### Formatting

```bash
swiftformat .
swiftformat --lint .
```

CI runs `swiftformat --lint .` on macOS only (the lint job).

### CI

GitHub Actions workflow at `.github/workflows/ci.yml` runs on both macOS 15 and
Linux (Ubuntu Noble with `swift:6.2-noble`). macOS job also runs swiftformat lint.

### Test counts

- `WorkspaceEngineTests` — 31 tests across Schema, CRUD, Query, MultipleKind, EdgeCase suites.
- `WorkspaceScannerTests` — 51 tests across FrontmatterParser, TitleExtraction, ParseContent, PathBasedRules, GlobMatcher, ConfigurationLoader, FileDiscovery, Integration suites.
- `FileWatcherTests` — 14 tests across FileWatcher, PathHelpers, WorkspaceScanner.watch suites.

Total: 96 tests.

## Key Design Decisions

1. **Engine has no filesystem knowledge.** `WorkspaceEngine` is a pure data store.
   `WorkspaceScanner` is the only thing that touches the filesystem. This makes the
   engine trivially testable and reusable (e.g., in a Swift-on-Server context where
   data arrives over the network).

2. **All frontmatter goes to `properties`.** Even properties that have a dedicated
   column in a kind extension table are also written to the `properties` table.
   This means `SELECT ... JOIN properties ...` always works regardless of kind.

3. **Extension table names use naive pluralization** (kind + "s"). Simple and predictable:
   `issue` → `issues`, `project` → `projects`, `recipe` → `recipes`.

4. **`scan(into:)` is async.** It clears the engine and repopulates from scratch.
   It loads the configuration (including path rules) and threads rules through to
   `parseContent`. The async `watch(engine:)` builds on top of it.

5. **All engine methods are async.** Uses GRDB's async `DatabaseQueue` overloads
   backed by a proper `SerialExecutor` on a dedicated `DispatchQueue`. This frees
   the calling cooperative thread while SQLite work runs.

6. **File watcher uses native APIs.** FSEvents on macOS, inotify on Linux. No
   polling. The watcher emits `.scanRequired` on overflow rather than trying to
   reconstruct what happened.

7. **`kind` and `title` are extracted from frontmatter, not stored in `properties`.**
   They live on `DocumentRecord` / the `docs` table. Everything else goes to properties.

8. **Path rules are a fallback.** Frontmatter `kind` always takes precedence.
   Rules provide convention-over-configuration for workspaces where directory
   structure implies document kind.

## Workspace + Issues

This project uses the Wuhu workspace system. Issues live at
`~/.wuhu/workspace/issues/`. Format: `WUHU-####`.

## Issue Workflow

When assigned a `WUHU-####` issue, create a new branch. See the umbrella
`AGENTS.md` for the full workflow.

## Collaboration

- Treat user concerns as likely-valid signals.
- Verify by inspecting the repo before concluding who's right.
- Prioritize clarity and maintainability.
