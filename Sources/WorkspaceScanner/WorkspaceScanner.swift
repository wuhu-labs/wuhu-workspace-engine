// WorkspaceScanner — file discovery, frontmatter parsing, and filesystem watching.
// This is the "impure" side that feeds the engine.

import Foundation
import WorkspaceContracts
import WorkspaceEngine

/// Scans a workspace directory, parses Markdown frontmatter, and populates a
/// ``WorkspaceEngine``.
///
/// `WorkspaceScanner` is the main entry point for the scanning pipeline. It
/// combines file discovery, frontmatter parsing, and configuration loading into
/// a single `scan(into:)` method that populates an engine with all documents
/// found in the workspace.
///
/// Individual steps (file discovery, frontmatter parsing, config loading) are
/// also exposed as standalone methods for testability and flexibility.
public struct WorkspaceScanner: Sendable {
  /// The root URL of the workspace directory to scan.
  public let root: URL

  /// Creates a scanner for the given workspace root.
  ///
  /// - Parameter root: The root URL of the workspace directory.
  public init(root: URL) {
    self.root = root
  }

  // MARK: - Configuration

  /// Loads the workspace configuration from `wuhu.yml` at the workspace root.
  ///
  /// Returns ``WorkspaceConfiguration.empty`` if the file doesn't exist.
  public func loadConfiguration() throws -> WorkspaceConfiguration {
    try ConfigurationLoader.loadConfiguration(from: root)
  }

  // MARK: - File Discovery

  /// Discovers all Markdown files in the workspace.
  ///
  /// Recursively scans the workspace root for `.md` files, skipping hidden
  /// files/directories and well-known directories like `node_modules`.
  ///
  /// - Returns: An array of URLs pointing to discovered Markdown files.
  public func discoverFiles() throws -> [URL] {
    try FileDiscovery.discoverMarkdownFiles(in: root)
  }

  // MARK: - Frontmatter Parsing

  /// Parses a single Markdown file and returns a ``DocumentRecord`` and properties.
  ///
  /// The method:
  /// 1. Reads the file content.
  /// 2. Parses YAML frontmatter.
  /// 3. Extracts `kind` (defaults to `.document`) and `title` (falls back to first heading).
  /// 4. Returns the document record and remaining properties.
  ///
  /// - Parameter fileURL: The URL of the Markdown file to parse.
  /// - Returns: A tuple of the document record and property dictionary.
  public func parseFile(at fileURL: URL) throws -> (record: DocumentRecord, properties: [String: String]) {
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let relativePath = FileDiscovery.relativePath(of: fileURL, to: root)
    return Self.parseContent(content, path: relativePath)
  }

  /// Parses Markdown content and returns a ``DocumentRecord`` and properties.
  ///
  /// This is a pure function (no filesystem access) for ease of testing.
  ///
  /// - Parameters:
  ///   - content: The raw Markdown content.
  ///   - path: The workspace-relative path for the resulting record.
  /// - Returns: A tuple of the document record and property dictionary.
  public static func parseContent(
    _ content: String,
    path: String,
  ) -> (record: DocumentRecord, properties: [String: String]) {
    let parsed = FrontmatterParser.parse(content)

    // Extract kind.
    let kind: Kind = if let kindString = parsed.fields["kind"] {
      Kind(rawValue: kindString)
    } else {
      .document
    }

    // Extract title: from frontmatter, or from the first heading.
    let title: String? = if let frontmatterTitle = parsed.fields["title"] {
      frontmatterTitle
    } else {
      FrontmatterParser.extractHeadingTitle(from: parsed.body)
    }

    let record = DocumentRecord(path: path, kind: kind, title: title)

    // Build properties: everything except `kind` and `title`.
    var properties = parsed.fields
    properties.removeValue(forKey: "kind")
    properties.removeValue(forKey: "title")

    return (record: record, properties: properties)
  }

  // MARK: - Full Scan

  /// Performs a full scan: discovers files, parses them, and populates the engine.
  ///
  /// This clears all existing documents from the engine and replaces them with
  /// the current state of the filesystem.
  ///
  /// - Parameter engine: The engine to populate with scanned documents.
  public func scan(into engine: WorkspaceEngine) throws {
    let files = try discoverFiles()

    // Clear existing data so the engine reflects current filesystem state.
    try engine.removeAllDocuments()

    for fileURL in files {
      let (record, properties) = try parseFile(at: fileURL)
      try engine.upsertDocument(record, properties: properties)
    }
  }
}
