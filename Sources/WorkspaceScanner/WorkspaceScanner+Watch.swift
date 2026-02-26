// WorkspaceScanner — live filesystem watching integration.

import Foundation
import WorkspaceContracts
import WorkspaceEngine

extension WorkspaceScanner {
  /// Starts watching the workspace and keeps the engine in sync.
  ///
  /// Performs an initial scan, then watches for filesystem changes and applies
  /// incremental updates to the engine. Events are processed individually as
  /// they arrive; the underlying watcher already coalesces events over a short
  /// window (100ms on macOS via FSEvents latency).
  ///
  /// For bulk operations (e.g., `git checkout`) that fire many events at once,
  /// a ``FileWatchEvent/scanRequired`` will trigger a full rescan.
  ///
  /// This method runs until the task is cancelled.
  ///
  /// - Parameter engine: The engine to keep in sync with the filesystem.
  public func watch(engine: WorkspaceEngine) async throws {
    // 1. Initial scan.
    try scan(into: engine)

    // 2. Start the file watcher.
    let watcher = FileWatcher(root: root)
    let events = watcher.start()

    // Clean up the watcher when the task is cancelled.
    defer { watcher.stop() }

    // 3. Process events as they arrive.
    for await event in events {
      if Task.isCancelled { break }

      switch event {
      case let .created(path), let .modified(path):
        processFileChange(path: path, engine: engine)

      case let .deleted(path):
        processFileDeletion(path: path, engine: engine)

      case .scanRequired:
        try scan(into: engine)
      }
    }
  }

  /// Processes a file creation or modification event.
  ///
  /// Re-parses the file and upserts it into the engine. Only `.md` files
  /// are processed; other file types are silently ignored.
  private func processFileChange(path: String, engine: WorkspaceEngine) {
    // Only process .md files.
    guard path.hasSuffix(".md") else { return }

    let fileURL = root.appendingPathComponent(path)

    // Make sure the file still exists (it might have been deleted in a rapid sequence).
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

    do {
      let (record, properties) = try parseFile(at: fileURL)
      try engine.upsertDocument(record, properties: properties)
    } catch {
      // If parsing fails, skip this file. It might be a partial write.
    }
  }

  /// Processes a file deletion event.
  ///
  /// Removes the document from the engine. Only `.md` files are processed.
  private func processFileDeletion(path: String, engine: WorkspaceEngine) {
    guard path.hasSuffix(".md") else { return }

    do {
      try engine.removeDocument(at: path)
    } catch {
      // Best-effort removal. The document might not exist in the engine
      // (e.g., it was a non-markdown file or was never indexed).
    }
  }
}
