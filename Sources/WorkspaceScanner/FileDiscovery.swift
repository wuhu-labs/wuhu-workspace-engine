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
  /// Returns workspace-relative paths (relative to `root`). Skips hidden files
  /// and directories (names starting with `.`) as well as well-known directories
  /// like `node_modules` and `.build`.
  ///
  /// - Parameter root: The root URL of the workspace directory.
  /// - Returns: An array of URLs pointing to discovered Markdown files.
  public static func discoverMarkdownFiles(in root: URL) throws -> [URL] {
    let fileManager = FileManager.default
    var results: [URL] = []

    guard let enumerator = fileManager.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
      options: [.producesRelativePathURLs],
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

      // Check if it's a directory — if so, continue recursion.
      let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
      guard resourceValues.isRegularFile == true else {
        continue
      }

      // Only include .md files.
      if fileURL.pathExtension.lowercased() == "md" {
        results.append(fileURL)
      }
    }

    return results.sorted { $0.relativePath < $1.relativePath }
  }

  /// Computes the workspace-relative path from an absolute file URL and a root URL.
  ///
  /// - Parameters:
  ///   - fileURL: The absolute URL to the file.
  ///   - root: The root URL of the workspace.
  /// - Returns: The workspace-relative path string.
  public static func relativePath(of fileURL: URL, to root: URL) -> String {
    let filePath = fileURL.standardizedFileURL.path
    let rootPath = root.standardizedFileURL.path

    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

    if filePath.hasPrefix(rootPrefix) {
      return String(filePath.dropFirst(rootPrefix.count))
    }

    // Fallback: use the relative path from the URL if available.
    return fileURL.relativePath
  }
}
