// WorkspaceScanner — file discovery for workspace directories.

import Foundation

/// Discovers Markdown files in a workspace directory.
public enum FileDiscovery {
  /// Directories to skip during file discovery.
  private static let skippedDirectories: Set<String> = [
    "node_modules",
    ".build",
    ".git",
  ]

  /// Recursively discovers all `.md` files in the given root directory.
  ///
  /// Returns absolute URLs to discovered files. Skips hidden files and
  /// directories (names starting with `.`) as well as well-known directories
  /// like `node_modules` and `.build`.
  ///
  /// - Parameter root: The root URL of the workspace directory.
  /// - Returns: An array of URLs pointing to discovered Markdown files, sorted
  ///   by their workspace-relative path.
  public static func discoverMarkdownFiles(in root: URL) throws -> [URL] {
    let fileManager = FileManager.default
    let rootPath = root.standardizedFileURL.path
    var results: [(url: URL, relative: String)] = []

    guard let enumerator = fileManager.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
      options: [],
    ) else {
      return []
    }

    for case let fileURL as URL in enumerator {
      let fileName = fileURL.lastPathComponent

      // Skip hidden files and directories.
      if fileName.hasPrefix(".") {
        enumerator.skipDescendants()
        continue
      }

      // Skip well-known directories.
      if skippedDirectories.contains(fileName) {
        enumerator.skipDescendants()
        continue
      }

      // Check if it's a regular file.
      let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
      guard resourceValues.isRegularFile == true else {
        continue
      }

      // Only include .md files.
      if fileURL.pathExtension.lowercased() == "md" {
        let rel = relativePath(of: fileURL, rootPath: rootPath)
        results.append((url: fileURL, relative: rel))
      }
    }

    return results
      .sorted { $0.relative < $1.relative }
      .map(\.url)
  }

  /// Computes the workspace-relative path from a file URL and a root URL.
  ///
  /// - Parameters:
  ///   - fileURL: The URL to the file (absolute or relative).
  ///   - root: The root URL of the workspace.
  /// - Returns: The workspace-relative path string.
  public static func relativePath(of fileURL: URL, to root: URL) -> String {
    relativePath(of: fileURL, rootPath: root.standardizedFileURL.path)
  }

  /// Internal helper that computes relative path from a pre-computed root path.
  private static func relativePath(of fileURL: URL, rootPath: String) -> String {
    let filePath = fileURL.standardizedFileURL.path
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

    if filePath.hasPrefix(rootPrefix) {
      return String(filePath.dropFirst(rootPrefix.count))
    }

    return fileURL.lastPathComponent
  }
}
