# Getting Started

This document has no frontmatter at all. Its title will be extracted from the
first `# Heading` line, and its kind will default to `document`.

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/wuhu-labs/wuhu-workspace-engine.git", from: "0.1.0")
```

## Basic Usage

```swift
import WorkspaceEngine
import WorkspaceScanner

let root = URL(fileURLWithPath: "/path/to/workspace")
let scanner = WorkspaceScanner(root: root)
let engine = try WorkspaceEngine()
try scanner.scan(into: engine)
```
