# AGENTS.md

## What is wuhu-workspace-engine

A workspace query engine for Wuhu. Scans Markdown files in a workspace directory,
parses their YAML frontmatter, indexes everything into an in-memory SQLite database
(via GRDB), and supports queries against the index.

## Architecture

Three targets with clear boundaries:

- **WorkspaceContracts**: Pure types and protocols. No dependencies. Safe to import
  from iOS apps or any other client — never pulls in GRDB or filesystem code.
- **WorkspaceEngine**: The pure query engine. Owns the SQLite database (GRDB),
  handles inserts/updates/deletes, runs queries, provides GRDB observation.
  Has no knowledge of the filesystem.
- **WorkspaceScanner**: The impure side. Discovers Markdown files, parses
  frontmatter, watches for filesystem changes (FSEvents on macOS, inotify on
  Linux), and feeds updates into the engine.

## Data Model

- **`docs` table**: Universal registry. Every document lands here (path, kind, title).
- **Kind tables** (e.g., `issues`): Extension tables with kind-specific columns.
  `path` is the FK back to `docs`.
- **`properties` table**: Key-value catch-all (`path`, `key`, `value`). ALL
  frontmatter is duplicated here, even if it also lives in a kind table.

Kinds are defined in `wuhu.yml`. Built-in kinds: `document`, `issue`.

## Local Dev

Prereqs:

- Swift 6.2 toolchain

```bash
swift build
swift test
```

Formatting:

```bash
swiftformat .
swiftformat --lint .
```

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
