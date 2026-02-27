// WorkspaceScanner — glob pattern matching for path-based rules.

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Matches file paths against glob patterns.
///
/// Supports `*` (matches any characters within a single path segment) and
/// `**` (matches zero or more path segments).
///
/// Uses `fnmatch(3)` under the hood with `FNM_PATHNAME` to enforce segment
/// boundaries for `*`. The `**` pattern is handled by expanding it into
/// the appropriate fnmatch behavior.
public enum GlobMatcher {
  /// Returns `true` if the given path matches the glob pattern.
  ///
  /// - Parameters:
  ///   - pattern: A glob pattern (e.g., `"issues/**"`, `"docs/*.md"`).
  ///   - path: A workspace-relative path to test (e.g., `"issues/0001.md"`).
  /// - Returns: Whether the path matches the pattern.
  public static func matches(pattern: String, path: String) -> Bool {
    // Handle ** patterns by trying multiple expansions.
    // fnmatch doesn't natively support ** for multi-segment matching,
    // so we handle it ourselves.

    if pattern.contains("**") {
      return matchesDoublestar(pattern: pattern, path: path)
    }

    // Simple case: no ** in pattern, use fnmatch directly.
    return fnmatch(pattern, path, FNM_PATHNAME) == 0
  }

  /// Handles patterns containing `**` by recursive decomposition.
  private static func matchesDoublestar(pattern: String, path: String) -> Bool {
    // Split on the first occurrence of "**".
    guard let range = pattern.range(of: "**") else {
      return fnmatch(pattern, path, FNM_PATHNAME) == 0
    }

    let prefix = String(pattern[pattern.startIndex ..< range.lowerBound])
    let suffix = String(pattern[range.upperBound ..< pattern.endIndex])

    // Normalize: if prefix ends with /, keep it. If suffix starts with /, keep it.
    // "issues/**" → prefix="issues/", suffix=""
    // "**/issues" → prefix="", suffix="/issues"
    // "a/**/b" → prefix="a/", suffix="/b"

    let pathComponents = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

    // Try matching ** against 0, 1, 2, ... path segments.
    // The prefix must match the beginning, the suffix must match the end.
    for splitAt in 0 ... pathComponents.count {
      // Build the "consumed prefix" path from components 0..<splitAt matched by everything before **
      // and the "remaining" path from components splitAt... matched by everything after **
      for endAt in splitAt ... pathComponents.count {
        let beforeDoublestar = pathComponents[0 ..< splitAt].joined(separator: "/")
        let afterDoublestar = pathComponents[endAt ..< pathComponents.count].joined(separator: "/")

        // Check if prefix matches beforeDoublestar.
        let prefixClean = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        let suffixClean = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix

        let prefixMatches: Bool = if prefixClean.isEmpty {
          beforeDoublestar.isEmpty
        } else {
          fnmatch(prefixClean, beforeDoublestar, FNM_PATHNAME) == 0
        }

        guard prefixMatches else { continue }

        // Check if suffix matches afterDoublestar.
        // The suffix may itself contain ** so recurse.
        let suffixMatches: Bool = if suffixClean.isEmpty {
          afterDoublestar.isEmpty
        } else if suffixClean.contains("**") {
          matchesDoublestar(pattern: suffixClean, path: afterDoublestar)
        } else {
          fnmatch(suffixClean, afterDoublestar, FNM_PATHNAME) == 0
        }

        if suffixMatches {
          return true
        }
      }
    }

    return false
  }
}
