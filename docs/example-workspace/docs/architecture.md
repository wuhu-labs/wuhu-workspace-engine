---
title: "Architecture Overview"
tag: important
---

# Architecture Overview

The workspace engine follows a strict separation between the pure query engine
and the impure filesystem layer.

## Targets

- **WorkspaceContracts** — types only, no dependencies.
- **WorkspaceEngine** — pure SQLite, no filesystem.
- **WorkspaceScanner** — file I/O, frontmatter parsing, watching.

## Data Flow

```
filesystem → WorkspaceScanner → WorkspaceEngine (SQLite) → queries
```

The engine never touches the filesystem. The scanner never runs queries.
