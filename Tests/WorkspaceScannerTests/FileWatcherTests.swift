import Foundation
import Testing
import WorkspaceContracts
import WorkspaceEngine
@testable import WorkspaceScanner

// MARK: - FileWatcher Tests

@Suite("FileWatcher")
struct FileWatcherTests {
  /// Creates a temporary directory for testing.
  private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("filewatcher-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Collects events from a watcher stream with a timeout.
  /// Returns accumulated events when either `count` events are received or `timeout` elapses.
  private func collectEvents(
    from stream: AsyncStream<FileWatchEvent>,
    count: Int,
    timeout: Duration = .seconds(5),
  ) async -> [FileWatchEvent] {
    var events: [FileWatchEvent] = []

    await withTaskGroup(of: [FileWatchEvent].self) { group in
      group.addTask {
        var collected: [FileWatchEvent] = []
        for await event in stream {
          collected.append(event)
          if collected.count >= count {
            break
          }
        }
        return collected
      }

      group.addTask {
        try? await Task.sleep(for: timeout)
        return []
      }

      // Take the first result that arrives.
      if let result = await group.next() {
        events = result
      }
      group.cancelAll()
    }

    return events
  }

  @Test("creating a file produces a created event")
  func fileCreation() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let watcher = FileWatcher(root: dir)
    let stream = watcher.start()
    defer { watcher.stop() }

    // Give the watcher time to set up.
    try await Task.sleep(for: .milliseconds(200))

    // Create a file.
    let filePath = dir.appendingPathComponent("new-file.md")
    try "# New File".write(to: filePath, atomically: true, encoding: .utf8)

    let events = await collectEvents(from: stream, count: 1, timeout: .seconds(5))

    // We should see at least one event for "new-file.md".
    let createdPaths = events.compactMap { event -> String? in
      if case let .created(path) = event { return path }
      return nil
    }

    #expect(createdPaths.contains("new-file.md"))
  }

  @Test("modifying a file produces a modified event")
  func fileModification() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    // Create a file first.
    let filePath = dir.appendingPathComponent("existing.md")
    try "# Original".write(to: filePath, atomically: true, encoding: .utf8)

    // Give the filesystem time to settle.
    try await Task.sleep(for: .milliseconds(100))

    let watcher = FileWatcher(root: dir)
    let stream = watcher.start()
    defer { watcher.stop() }

    // Give the watcher time to set up.
    try await Task.sleep(for: .milliseconds(200))

    // Modify the file.
    try "# Modified Content".write(to: filePath, atomically: true, encoding: .utf8)

    let events = await collectEvents(from: stream, count: 1, timeout: .seconds(5))

    // We should see a modified (or created, since atomicWrite creates a temp + rename) event.
    let relevantPaths = events.compactMap { event -> String? in
      switch event {
      case let .modified(path): return path
      case let .created(path): return path
      default: return nil
      }
    }

    #expect(relevantPaths.contains("existing.md"))
  }

  @Test("deleting a file produces a deleted event")
  func fileDeletion() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    // Create a file first.
    let filePath = dir.appendingPathComponent("to-delete.md")
    try "# Delete Me".write(to: filePath, atomically: true, encoding: .utf8)

    // Give the filesystem time to settle.
    try await Task.sleep(for: .milliseconds(100))

    let watcher = FileWatcher(root: dir)
    let stream = watcher.start()
    defer { watcher.stop() }

    // Give the watcher time to set up.
    try await Task.sleep(for: .milliseconds(200))

    // Delete the file.
    try FileManager.default.removeItem(at: filePath)

    let events = await collectEvents(from: stream, count: 1, timeout: .seconds(5))

    // We should see a deleted event.
    let deletedPaths = events.compactMap { event -> String? in
      if case let .deleted(path) = event { return path }
      return nil
    }

    #expect(deletedPaths.contains("to-delete.md"))
  }

  @Test("events in subdirectories include relative path")
  func subdirectoryEvent() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let subDir = dir.appendingPathComponent("notes")
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

    let watcher = FileWatcher(root: dir)
    let stream = watcher.start()
    defer { watcher.stop() }

    // Give the watcher time to set up.
    try await Task.sleep(for: .milliseconds(200))

    // Create a file in the subdirectory.
    let filePath = subDir.appendingPathComponent("note.md")
    try "# Note".write(to: filePath, atomically: true, encoding: .utf8)

    let events = await collectEvents(from: stream, count: 1, timeout: .seconds(5))

    let createdPaths = events.compactMap { event -> String? in
      if case let .created(path) = event { return path }
      return nil
    }

    #expect(createdPaths.contains("notes/note.md"))
  }

  @Test("hidden files are skipped")
  func hiddenFilesSkipped() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let watcher = FileWatcher(root: dir)
    let stream = watcher.start()
    defer { watcher.stop() }

    try await Task.sleep(for: .milliseconds(200))

    // Create a hidden file.
    let hiddenFile = dir.appendingPathComponent(".hidden-file")
    try "secret".write(to: hiddenFile, atomically: true, encoding: .utf8)

    // Create a visible file to confirm we do get events.
    try await Task.sleep(for: .milliseconds(100))
    let visibleFile = dir.appendingPathComponent("visible.md")
    try "# Visible".write(to: visibleFile, atomically: true, encoding: .utf8)

    let events = await collectEvents(from: stream, count: 1, timeout: .seconds(5))

    let allPaths = events.compactMap { event -> String? in
      switch event {
      case let .created(path): return path
      case let .modified(path): return path
      case let .deleted(path): return path
      case .scanRequired: return nil
      }
    }

    // Should not contain the hidden file.
    #expect(!allPaths.contains(".hidden-file"))
    // Should contain the visible file.
    #expect(allPaths.contains("visible.md"))
  }

  @Test("stop ends the event stream")
  func stopEndsStream() async throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let watcher = FileWatcher(root: dir)
    let stream = watcher.start()

    try await Task.sleep(for: .milliseconds(200))

    watcher.stop()

    // The stream should end (for-await should complete).
    var eventCount = 0
    for await _ in stream {
      eventCount += 1
    }

    // Stream has ended.
    #expect(eventCount == 0)
  }
}

// MARK: - FileWatcher Path Helpers Tests

@Suite("FileWatcher Path Helpers")
struct FileWatcherPathHelperTests {
  @Test("shouldSkip returns true for hidden components")
  func skipHidden() {
    #expect(FileWatcher.shouldSkip(".git") == true)
    #expect(FileWatcher.shouldSkip(".hidden") == true)
    #expect(FileWatcher.shouldSkip(".build") == true)
  }

  @Test("shouldSkip returns true for node_modules")
  func skipNodeModules() {
    #expect(FileWatcher.shouldSkip("node_modules") == true)
  }

  @Test("shouldSkip returns false for normal names")
  func dontSkipNormal() {
    #expect(FileWatcher.shouldSkip("notes") == false)
    #expect(FileWatcher.shouldSkip("docs") == false)
    #expect(FileWatcher.shouldSkip("README.md") == false)
  }

  @Test("shouldSkipPath checks all path components")
  func skipPathComponents() {
    #expect(FileWatcher.shouldSkipPath(".git/HEAD") == true)
    #expect(FileWatcher.shouldSkipPath("node_modules/package/file.md") == true)
    #expect(FileWatcher.shouldSkipPath("notes/todo.md") == false)
    #expect(FileWatcher.shouldSkipPath("deep/.hidden/file.md") == true)
  }

  @Test("relativePath strips root prefix")
  func relativePathStripping() {
    let watcher = FileWatcher(root: URL(fileURLWithPath: "/workspace"))
    #expect(watcher.relativePath(for: "/workspace/docs/hello.md") == "docs/hello.md")
    #expect(watcher.relativePath(for: "/workspace/file.md") == "file.md")
  }
}

// MARK: - WorkspaceScanner.watch Integration Tests

@Suite("WorkspaceScanner.watch")
struct WorkspaceScannerWatchTests {
  /// Creates a temporary workspace directory with an initial file.
  private func makeWorkspace() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("scanner-watch-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Create an initial Markdown file.
    try """
    ---
    title: "Initial Doc"
    kind: document
    ---

    # Initial Doc

    Some content.
    """.write(to: dir.appendingPathComponent("initial.md"), atomically: true, encoding: .utf8)

    return dir
  }

  @Test("watch performs initial scan")
  func initialScan() async throws {
    let dir = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: dir) }

    let scanner = WorkspaceScanner(root: dir)
    let engine = try WorkspaceEngine()

    // Start watching in a task, cancel after a short time.
    let task = Task {
      try await scanner.watch(engine: engine)
    }

    // Give the initial scan time to complete.
    try await Task.sleep(for: .milliseconds(500))
    task.cancel()

    // Wait for the task to finish.
    _ = try? await task.value

    // The initial document should be in the engine.
    let doc = try await engine.document(at: "initial.md")
    #expect(doc != nil)
    #expect(doc?.record.title == "Initial Doc")
  }

  @Test("watch picks up new files")
  func watchNewFile() async throws {
    let dir = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: dir) }

    let scanner = WorkspaceScanner(root: dir)
    let engine = try WorkspaceEngine()

    let task = Task {
      try await scanner.watch(engine: engine)
    }

    // Give the initial scan and watcher time to start.
    try await Task.sleep(for: .milliseconds(500))

    // Create a new Markdown file.
    try """
    ---
    title: "New Note"
    kind: document
    status: draft
    ---

    # New Note
    """.write(to: dir.appendingPathComponent("new-note.md"), atomically: true, encoding: .utf8)

    // Wait for the event to be processed.
    try await Task.sleep(for: .seconds(2))
    task.cancel()
    _ = try? await task.value

    let doc = try await engine.document(at: "new-note.md")
    #expect(doc != nil)
    #expect(doc?.record.title == "New Note")
  }

  @Test("watch removes deleted files")
  func watchDeletedFile() async throws {
    let dir = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: dir) }

    let scanner = WorkspaceScanner(root: dir)
    let engine = try WorkspaceEngine()

    let task = Task {
      try await scanner.watch(engine: engine)
    }

    // Give the initial scan and watcher time to start.
    try await Task.sleep(for: .milliseconds(500))

    // Verify the initial doc is there.
    let initialDoc = try await engine.document(at: "initial.md")
    #expect(initialDoc != nil)

    // Delete the file.
    try FileManager.default.removeItem(at: dir.appendingPathComponent("initial.md"))

    // Wait for the event to be processed.
    try await Task.sleep(for: .seconds(2))
    task.cancel()
    _ = try? await task.value

    let deletedDoc = try await engine.document(at: "initial.md")
    #expect(deletedDoc == nil)
  }
}
